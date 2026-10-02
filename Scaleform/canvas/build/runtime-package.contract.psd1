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
  HostSha256 = 'B634EB1D9C621288408C35DBC01437A20F7ACCFED5E3516437C28D5021598802'
  RegistrySha256 = 'B4F4D28CC5FE08D9A25D4E532F352FCDA566F7A6D427AEE3AC89B3A8FB13487D'
  HostSourceSha256 = 'B8D280D4B053D598A7DD50746B7952DF4A69EA51E8845862FAE22B604FE58345'
  RegistryRequiredTokens = @(
    'BuildCanvasDatagramBody'
    'TryPublishCanvasDatagram'
  )
}
