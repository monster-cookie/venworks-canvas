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
  HostSha256 = 'B37D2E7BD9E2E1949BC4FF389508D09A86200A2A9F1D5F35600B3B41349123C9'
  RegistrySha256 = '029115584FE54503C4E38E029B3805FFC2D7CF5F63095D1C4870F3F9F7E9629D'
  HostSourceSha256 = 'DF745DF618B0F7579A2901F2C9EB020ACD73E723A2704959766F4051B0E4FCA7'
  RegistryRequiredTokens = @(
    'BuildCanvasDatagramBody'
    'TryPublishCanvasDatagram'
  )
}
