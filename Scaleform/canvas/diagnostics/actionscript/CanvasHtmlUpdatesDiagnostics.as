package
{
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.Sprite;
   import flash.display.Shape;
   import flash.events.Event;
   import flash.text.TextField;
   import flash.geom.Rectangle;

   public final class CanvasHtmlUpdatesDiagnostics
   {
      public static function run() : void
      {
         testInitialCommit();
         var html:String = '<!DOCTYPE html><html><head><title>Update diagnostic</title><style>body { width: 800px; } .panel { width: 200px; height: 100px; } vw-meter { width: 100px; height: 10px; }</style></head><body><div class="panel"><p>STATIC</p></div><div class="panel"><p data-vw-text="label"></p><vw-meter value="health" min="0" max="100"></vw-meter></div></body></html>';
         var parsed:CanvasHtmlParseResult = new CanvasHtmlParser().parse(html,"index.html");
         check(parsed.success,"update document parse failed");
         var resource:CanvasHtmlResource = new CanvasHtmlResource("index.html","html",html,html.length,parsed.document);
         var loaded:CanvasHtmlLoadResult = new CanvasHtmlLoadResult(true,false,parsed.document,[resource],null);
         var mount:Sprite = new Sprite();
         var session:CanvasHtmlSession = new CanvasHtmlSession(mount,loaded);
         check(session.initialize() == null,"update session initialization failed");
         session.setData({label:"FIRST",health:25});
         session.setData({label:"LATEST",health:50});
         var fixed:DisplayObject = find(mount,"STATIC");
         var bound:DisplayObject = find(mount,"LATEST");
         var meter:DisplayObject = find(mount,null);
         check(fixed != null && bound != null && meter != null,"rendered objects unavailable");
         var detached:int = 0;
         fixed.addEventListener(Event.REMOVED,function(event:Event):void { detached++; });
         session.setData({label:"CHANGED",health:75});
         check(find(mount,"STATIC") === fixed && detached == 0,"unrelated panel was reconstructed or detached");
         check(find(mount,"CHANGED") === bound,"bound text identity was replaced");
         check(find(mount,null) === meter,"bound meter identity was replaced");
         var rejected:Boolean = false;
         try { session.setData({label:"INVALID",health:"bad"}); } catch(error:*) { rejected = true; }
         check(rejected && find(mount,"CHANGED") === bound,"invalid snapshot replaced valid display");
         session.dispose();
         check(mount.numChildren == 0,"display survived disposal");
      }

      private static function document(body:String, attributes:String = "", css:String = "") : CanvasHtmlLoadResult
      {
         var html:String = '<!DOCTYPE html><html><head><title>Session regression</title><style>'+css+'</style></head><body '+attributes+'>'+body+'</body></html>';
         var parsed:CanvasHtmlParseResult = new CanvasHtmlParser().parse(html,"index.html");
         check(parsed.success,"session fixture parse failed: "+parsed.diagnostic);
         return new CanvasHtmlLoadResult(true,false,parsed.document,[new CanvasHtmlResource("index.html","html",html,html.length,parsed.document)],null);
      }

      private static function testInitialCommit() : void
      {
         var root:Sprite = new Sprite();
         var center:Sprite = new Sprite(); center.name = "CenterGroup_mc"; root.addChild(center);
         var target:Sprite = new Sprite(); target.name = "ReticleBase_mc"; center.addChild(target);
         var manager:CanvasHudTargets = new CanvasHudTargets(root,"player",null,null);
         var mount:Sprite = new Sprite();
         var markup:String = '<vw-hud-target target="player.crosshair" disabled="true"></vw-hud-target><vw-state name="clear" event="test.clear"><p>CLEAR</p></vw-state>';
         var session:CanvasHtmlSession = new CanvasHtmlSession(mount,document(markup),manager,"static");
         check(session.initialize() == null && target.mask != null,"initial HTML/2 target was not applied");
         session.setViewport(1000,700);
         check(target.mask != null,"pre-snapshot viewport lost target");
         session.dispose(); check(target.mask == null,"session unload did not release target");
         var states:String = '<vw-state name="hide" event="test.hide"><vw-hud-target target="player.crosshair" disabled="true"></vw-hud-target></vw-state><vw-state name="clear" event="test.clear"><p>CLEAR</p></vw-state>';
         session = new CanvasHtmlSession(mount,document(states),manager,"states");
         check(session.initialize() == null && target.mask == null,"inactive state suppressed target");
         session.dispatch("test.hide"); check(target.mask != null,"pre-snapshot state did not apply target");
         session.dispatch("test.clear"); check(target.mask == null,"empty target commit did not release suppression");
         session.dispatch("test.hide");
         var rejectedLayout:Boolean = false;
         try { session.setHostLayout({visibleWidth:-1,visibleHeight:700,safeX:0,safeY:0,visibleX:0,visibleY:0}); } catch(layoutError:*) { rejectedLayout = true; }
         check(rejectedLayout && target.mask != null,"rejected layout changed target ownership");
         session.setHostLayout({visibleWidth:1000,visibleHeight:700,safeX:0,safeY:0,visibleX:0,visibleY:0});
         check(target.mask != null,"valid layout retry lost suppression"); session.dispose();
         session = new CanvasHtmlSession(mount,document('<p>BODY</p>','data-vw-opacity="opacity" data-vw-y="position"'));
         check(session.initialize() == null,"body binding initialization failed");
         session.setData({opacity:0.25,position:12});
         var body:DisplayObject = DisplayObjectContainer(DisplayObjectContainer(mount.getChildAt(0)).getChildAt(0)).getChildAt(0);
         check(body.alpha == 0.25 && body.y == 12,"body presentation binding ignored");
         var rejected:Boolean = false;
         try { session.setData({opacity:2,position:12}); } catch(error:*) { rejected = true; }
         check(rejected && body.alpha == 0.25,"invalid body binding changed display"); session.dispose();
         var svg:String = '<svg viewBox="0 0 100 100" width="20" height="30"><rect width="100" height="100" fill="#ffffff"></rect></svg>';
         session = new CanvasHtmlSession(mount,document(svg,"","svg { width: 40px; }"));
         check(session.initialize() == null,"standard inline SVG dimensions failed");
         var svgBody:DisplayObjectContainer = DisplayObjectContainer(DisplayObjectContainer(DisplayObjectContainer(mount.getChildAt(0)).getChildAt(0)).getChildAt(0));
         var svgDisplay:DisplayObject = svgBody.getChildAt(0);
         var bounds:Rectangle = svgDisplay.getBounds(svgDisplay);
         check(bounds.width >= 39 && bounds.width <= 41 && bounds.height >= 29 && bounds.height <= 31,"CSS did not override SVG dimensions");
         session.dispose(); manager.dispose();
      }

      private static function find(root:DisplayObject, text:String) : DisplayObject
      {
         if(text == null && root is Shape) return root;
         if(root is TextField && TextField(root).text == text) return root;
         if(root is DisplayObjectContainer)
         {
            var container:DisplayObjectContainer = root as DisplayObjectContainer;
            for(var i:int = 0; i < container.numChildren; i++)
            {
               var result:DisplayObject = find(container.getChildAt(i),text);
               if(result != null) return result;
            }
         }
         return null;
      }

      private static function check(value:Boolean, message:String) : void
      {
         if(!value) throw new Error(message);
      }
   }
}
