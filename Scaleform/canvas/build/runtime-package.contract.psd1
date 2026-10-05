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
    'CanvasBootScreen'
    'VENWORKS CANVAS OS BOOTING'
    'VWCANVAS TEX'
  )
  HostForbiddenTokens = @('VWCANVAS_HTML/3')
  HostSha256 = 'C3361E6442E75B71C50E8452383F0D795E7E989DF6EA3CF19A168992DDF403A1'
  RegistrySha256 = '029115584FE54503C4E38E029B3805FFC2D7CF5F63095D1C4870F3F9F7E9629D'
  HostSourceSha256 = '87C0A7EF26EC2A2E1956D145392C13B839D3A1B94E3BD1F258296C34AAD2FAC6'
  RegistryRequiredTokens = @(
    'BuildCanvasDatagramBody'
    'TryPublishCanvasDatagram'
  )
}
