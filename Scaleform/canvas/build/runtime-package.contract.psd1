@{
  Schema = 'VWCANVAS_RUNTIME_PACKAGE/1'
  HostEntry = 'interface/venworkscui.swf'
  RegistryEntry = 'scripts/venworks/canvas/registry.pex'
  HostRequiredTokens = @(
    'VWCANVAS_CONSUMER/1'
    'VWCANVAS_CONSUMER/2'
    'VWCANVAS_CONSUMER/3'
    'VWCANVAS_HTML/2'
    'VWCANVAS_RUNTIME/1'
    'CanvasHtmlRetainedTree'
    'CanvasHudTargets'
    'setHostLayout'
    'CanvasSvgGeometry'
    'CanvasHtmlNativeSymbol'
    'CanvasDatagramCodec'
    'latest'
    'fifo'
    'PLAYER_STATUS_DATA'
    'PlayerStatusData'
  )
  HostForbiddenTokens = @('VWCANVAS_HTML/3')
  HostSha256 = '2CB31612C7A27A4CB429B509A6B730E58A5D80D842FB75BE85CE6558322FAA20'
  RegistrySha256 = 'C6751417229FF8BF2593AF4B77DCEEEA66610AE5C49BAA68E3254B5A8ADB4B43'
  HostSourceSha256 = '98457848CA3C5098B9D41282E4630234426508FBBE33F2F7D1FA748EC69C803F'
  RegistryRequiredTokens = @(
    'BuildCanvasDatagramBody'
    'TryPublishCanvasDatagram'
  )
}
