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
  HostSha256 = 'BF04F1CE90D8E3A8281320A3CE23E12515749232F3668A2B70DF8CCEF7A134D4'
  RegistrySha256 = '029115584FE54503C4E38E029B3805FFC2D7CF5F63095D1C4870F3F9F7E9629D'
  HostSourceSha256 = 'F79A185C0BBCA37B2705CFB367BEB4AE21B84D00070B96801DFCF5350294141F'
  RegistryRequiredTokens = @(
    'BuildCanvasDatagramBody'
    'TryPublishCanvasDatagram'
  )
}
