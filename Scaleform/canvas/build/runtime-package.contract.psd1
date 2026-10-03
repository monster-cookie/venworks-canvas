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
  HostSha256 = '639DF7C70E604C161B553E572000787CEC8E955D3880B6E584A854C3C2D0572D'
  RegistrySha256 = '07B3B271E32C4D8F298F502C8DBD551E2E52A4C748FCBD5EFC2339AFF397BD7E'
  HostSourceSha256 = '35598757941A1C9F93B3178EB89E4AF9017681B47BF2E97677148FEE10A82E67'
  RegistryRequiredTokens = @(
    'BuildCanvasDatagramBody'
    'TryPublishCanvasDatagram'
  )
}
