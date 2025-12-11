{ ... }:
{
  # Use native macOS ssh-agent instead of GPG agent for SSH
  # macOS ssh-agent integrates with Keychain for seamless passphrase storage
  programs.gnupg.agent.enableSSHSupport = false;
}
