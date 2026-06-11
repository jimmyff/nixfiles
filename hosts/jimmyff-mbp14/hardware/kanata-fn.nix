# MacBook internal keyboard top row, injected into the shared kanata template.
# kanata's grab sits below Apple's fn->media translation and the virtual keyboard
# isn't treated as an Apple keyboard, so re-emitted F-keys lose their media
# behaviour — we emit the media actions directly (tap = native action).
# Layout matches the printed legends:
#   F1/F2 brightness · F7-F9 prev/play/next · F10 mute · F11/F12 volume
# F3-F6 (Mission Control, Spotlight, Dictation, DND) are left unmapped for now.
# Caps Lock is mapped here too — the grab otherwise leaves it dead.
{
  aliases = ''
    (defalias
      f1 brdown
      f2 brup
      f7 prev
      f8 MediaPlayPause
      f9 next
      f10 VolumeMute
      f11 VolumeDown
      f12 VolumeUp
    )'';
  defsrc = "  f1 f2  f7 f8 f9  f10 f11 f12  caps";
  base = "  @f1 @f2  @f7 @f8 @f9  @f10 @f11 @f12  caps";
  gamemode = "  @f1 @f2  @f7 @f8 @f9  @f10 @f11 @f12  caps";
}
