//go:build darwin || linux

package cmd

import (
	"os"
	"os/exec"
	"os/signal"
	"sync"
	"syscall"
)

// Live process groups for in-flight test runs. Setpgid detaches children from
// the terminal's foreground group, so a Ctrl-C would no longer reach them —
// the signal handler forwards it by killing every registered group.
var (
	procGroupMu sync.Mutex
	procGroups  = map[int]bool{}
	signalOnce  sync.Once
)

// setProcGroup makes cmd the leader of its own process group so the whole
// tree (dart VM grandchildren included) can be killed on timeout. Must be
// called before Start.
func setProcGroup(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
}

// registerProcGroup records a started command's process group for the signal
// handler and returns an unregister func.
func registerProcGroup(cmd *exec.Cmd) func() {
	if cmd.Process == nil {
		return func() {}
	}
	pid := cmd.Process.Pid
	procGroupMu.Lock()
	procGroups[pid] = true
	procGroupMu.Unlock()
	return func() {
		procGroupMu.Lock()
		delete(procGroups, pid)
		procGroupMu.Unlock()
	}
}

// killProcGroup SIGKILLs cmd's process group (pgid == child pid under
// Setpgid), falling back to killing the direct child.
func killProcGroup(cmd *exec.Cmd) {
	if cmd.Process == nil {
		return
	}
	if err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL); err != nil {
		cmd.Process.Kill()
	}
}

// installSignalHandler kills all registered process groups on SIGINT/SIGTERM
// and exits with the conventional interrupted status. Installed at most once.
func installSignalHandler() {
	signalOnce.Do(func() {
		ch := make(chan os.Signal, 1)
		signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
		go func() {
			<-ch
			procGroupMu.Lock()
			for pid := range procGroups {
				syscall.Kill(-pid, syscall.SIGKILL)
			}
			procGroupMu.Unlock()
			os.Exit(130)
		}()
	})
}
