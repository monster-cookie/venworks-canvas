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
  HostSha256 = '9D7D997A3C7716A553E5A4AA9E423870A5F3E20DA0E7ECDD67FD6E687ED1EFC3'
  RegistrySha256 = '029115584FE54503C4E38E029B3805FFC2D7CF5F63095D1C4870F3F9F7E9629D'
  HostSourceSha256 = 'B7860A31517D222D132704E3D784950C3C7F1CAD6448388670C3C77F8FD10366'
  RegistryRequiredTokens = @(
    'BuildCanvasDatagramBody'
    'TryPublishCanvasDatagram'
  )
}
