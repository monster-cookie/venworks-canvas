package
{
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.Sprite;
   import flash.display.Shape;
   import flash.events.Event;
   import flash.text.TextField;

   public final class CanvasHtmlUpdatesDiagnostics
   {
      public static function run() : void
      {
         var html:String = '<!DOCTYPE html><html><head><title>Update diagnostic</title><style>body { width: 800px; } .panel { width: 200px; height: 100px; } vw-meter { width: 100px; height: 10px; }</style></head><body><div class="panel"><p>STATIC</p></div><div class="panel"><p data-vw-text="label"></p><vw-meter value="health" min="0" max="100"></vw-meter></div></body></html>';
         var parsed:CanvasHtmlParseResult = new CanvasHtmlParser().parse(html,"index.html");
         check(parsed.success,"update document parse failed");
         var resource:CanvasHtmlResource = new CanvasHtmlResource("index.html","html",html,html.length,parsed.document);
         var loaded:CanvasHtmlLoadResult = new CanvasHtmlLoadResult(true,false,parsed.document,[resource],null);
         var mount:Sprite = new Sprite();
         var session:CanvasHtmlSession = new CanvasHtmlSession(mount,loaded,true);
         check(session.initialize() == null,"update session initialization failed");
         session.setData({label:"FIRST",health:25});
         session.setData({label:"LATEST",health:50});
         check(session.getUpdateState().revision == 0 && session.getUpdateState().pending,"updates did not coalesce");
         mount.dispatchEvent(new Event(Event.ENTER_FRAME));
         check(session.getUpdateState().revision == 1 && session.getUpdateState().diagnostic == null,"first queued update failed");
         var fixed:DisplayObject = find(mount,"STATIC");
         var bound:DisplayObject = find(mount,"LATEST");
         var meter:DisplayObject = find(mount,null);
         check(fixed != null && bound != null && meter != null,"rendered objects unavailable");
         var detached:int = 0;
         fixed.addEventListener(Event.REMOVED,function(event:Event):void { detached++; });
         session.setData({label:"CHANGED",health:75});
         mount.dispatchEvent(new Event(Event.ENTER_FRAME));
         check(find(mount,"STATIC") === fixed && detached == 0,"unrelated panel was reconstructed or detached");
         check(find(mount,"CHANGED") === bound,"bound text identity was replaced");
         check(find(mount,null) === meter,"bound meter identity was replaced");
         var rejected:Boolean = false;
         try { session.setData({label:"INVALID",health:"bad"}); } catch(error:*) { rejected = true; }
         check(rejected && find(mount,"CHANGED") === bound,"invalid snapshot replaced valid display");
         session.setData({label:"UNLOADED",health:10});
         session.dispose();
         mount.dispatchEvent(new Event(Event.ENTER_FRAME));
         check(mount.numChildren == 0 && !session.getUpdateState().pending,"pending update survived disposal");
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
