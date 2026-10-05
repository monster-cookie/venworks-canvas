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
  )
  HostForbiddenTokens = @('VWCANVAS_HTML/3')
  HostSha256 = '75915AB50544B72808E6E66621CF3780AB058D23EDDB700A51FA5D6E21E0B97A'
  RegistrySha256 = '029115584FE54503C4E38E029B3805FFC2D7CF5F63095D1C4870F3F9F7E9629D'
  HostSourceSha256 = 'B2C9A0993590736DFCD118AC690B42B8BC1B3C1884BFAF97477CC3ED6F657880'
  RegistryRequiredTokens = @(
    'BuildCanvasDatagramBody'
    'TryPublishCanvasDatagram'
  )
}
