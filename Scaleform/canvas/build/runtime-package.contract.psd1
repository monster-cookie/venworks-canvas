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
  HostSha256 = '0804CCA4EF6346F29CDC51A79C673A68BD7EB076D6EA24B0C21D7AAB4372929F'
  RegistrySha256 = '504C00BCA443D9CBA39D99DF3C381C379D38E5060DC4C6CD96F41CA60C72A815'
  HostSourceSha256 = 'CE6FBAE4CEDC7727A079A6D787E0D6B9F084D3AF0DE02A769A5DD901D2662098'
  RegistryRequiredTokens = @(
    'BuildCanvasDatagramBody'
    'TryPublishCanvasDatagram'
  )
}
