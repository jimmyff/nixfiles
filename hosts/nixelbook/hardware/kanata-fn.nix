# Pixelbook (Chromebook) top row, injected into the shared kanata template.
# Tap = F-key, hold = brightness/media/volume:
#   f5/f6 brightness down/up · f7 play/pause · f8 mute · f9/f10 volume down/up
{
  aliases = ''
    (defalias
      f5 (multi f24 (tap-hold 200 300 f5 brdown))
      f6 (multi f24 (tap-hold 200 300 f6 brup))
      f7 (multi f24 (tap-hold 200 300 f7 MediaPlayPause))
      f8 (multi f24 (tap-hold 200 300 f8 VolumeMute))
      f9 (multi f24 (tap-hold 200 300 f9 VolumeDown))
      f10 (multi f24 (tap-hold 200 300 f10 VolumeUp))
    )'';
  defsrc = "  f5 f6  f7  f8 f9 f10";
  base = "  @f5 @f6  @f7  @f8 @f9 @f10";
  gamemode = "  @f5 @f6  @f7  @f8 @f9 @f10";
}
