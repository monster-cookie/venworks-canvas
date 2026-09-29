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
  )
  HostForbiddenTokens = @('VWCANVAS_HTML/3')
  HostSha256 = '57C78ACA2ADB5E9582CDB8A20358038739A32616655233AB71AD5F7EF46F90E2'
  RegistrySha256 = 'C6751417229FF8BF2593AF4B77DCEEEA66610AE5C49BAA68E3254B5A8ADB4B43'
  HostSourceSha256 = 'DD407FEB5AE94854877AB1E9487F8794631508D0260E657D0968882891982BB3'
  RegistryRequiredTokens = @(
    'BuildCanvasDatagramBody'
    'TryPublishCanvasDatagram'
  )
}
