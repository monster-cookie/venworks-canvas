package
{
   import flash.utils.Dictionary;

   public final class CanvasCssCascade
   {
      private static const INHERITED:Array = ["color","font-family","font-size","font-weight","text-align","line-height"];

      private var rules:Array;

      private var matchWork:int;

      private var matchWorkExceeded:Boolean;

      private var identityCache:Dictionary;

      public function CanvasCssCascade(param1:Array)
      {
         this.rules = param1 == null ? [] : param1.concat();
      }

      public function beginPass() : void
      {
         this.matchWork = 0;
         this.matchWorkExceeded = false;
         this.identityCache = new Dictionary(false);
      }

      public function get exceededMatchWork() : Boolean
      {
         return this.matchWorkExceeded;
      }

      public function computeStyle(param1:CanvasHtmlNode, param2:Array, param3:Object) : Object
      {
         var style:Object = this.defaultStyle(param1 == null ? "" : param1.name,param3);
         var priorities:Object = {};
         var rule:Object = null;
         var declaration:Object = null;
         var priority:Number = 0;
         var name:String = null;
         for each(rule in this.rules)
         {
            if(this.matches(rule.selector,param1,param2))
            {
               priority = Number(rule.specificity) * 100000 + Number(rule.order);
               for each(declaration in rule.declarations)
               {
                  name = String(declaration.name);
                  if(!priorities.hasOwnProperty(name) || priority >= Number(priorities[name]))
                  {
                     style[name] = declaration.value;
                     priorities[name] = priority;
                  }
               }
            }
            if(this.matchWorkExceeded)
            {
               return null;
            }
         }
         return style;
      }

      public function inheritedStyle(param1:Object) : Object
      {
         return this.defaultStyle("",param1);
      }

      private function defaultStyle(param1:String, param2:Object) : Object
      {
         var style:Object = {
            "display":this.defaultDisplay(param1),
            "flex-direction":"column",
            "width":"auto",
            "height":"auto",
            "margin-top":"0",
            "margin-right":"0",
            "margin-bottom":"0",
            "margin-left":"0",
            "padding-top":"0",
            "padding-right":"0",
            "padding-bottom":"0",
            "padding-left":"0",
            "gap":"0",
            "color":"#ffffff",
            "background-color":"transparent",
            "border-color":"transparent",
            "border-width":"0",
            "border-style":"none",
            "font-family":"$MAIN_Font_Bold",
            "font-size":"18px",
            "font-weight":"normal",
            "text-align":"left",
            "line-height":"normal",
            "overflow":"visible",
            "opacity":"1",
            "position":"static",
            "left":"0",
            "top":"0",
            "z-index":"0"
         };
         var name:String = null;
         if(param2 != null)
         {
            for each(name in INHERITED)
            {
               if(param2.hasOwnProperty(name))
               {
                  style[name] = param2[name];
               }
            }
         }
         if(param1 == "h1")
         {
            style["font-size"] = "32px";
            style["font-weight"] = "bold";
         }
         else if(param1 == "h2")
         {
            style["font-size"] = "28px";
            style["font-weight"] = "bold";
         }
         else if(param1 == "h3")
         {
            style["font-size"] = "24px";
            style["font-weight"] = "bold";
         }
         else if(param1 == "h4" || param1 == "h5" || param1 == "h6" || param1 == "button")
         {
            style["font-weight"] = "bold";
         }
         if(param1 == "button")
         {
            style["padding-top"] = "6px";
            style["padding-right"] = "10px";
            style["padding-bottom"] = "6px";
            style["padding-left"] = "10px";
            style["background-color"] = "#303030";
            style["border-color"] = "#ffffff";
            style["border-width"] = "1px";
            style["border-style"] = "solid";
         }
         return style;
      }

      private function defaultDisplay(param1:String) : String
      {
         if(param1 == "span" || param1 == "br" || param1 == "button" || param1 == "img" || param1 == "svg" || param1 == "vw-meter")
         {
            return "inline";
         }
         return "block";
      }

      private function matches(param1:Array, param2:CanvasHtmlNode, param3:Array) : Boolean
      {
         if(!this.consumeMatchWork())
         {
            return false;
         }
         if(param1 == null || param1.length == 0 || param2 == null || !this.matchesSimple(param1[param1.length - 1],param2))
         {
            return false;
         }
         var ancestors:Array = param3 == null ? [] : param3;
         var states:Array = [];
         if(!this.pushMatchState(states,param1.length - 1,ancestors.length - 1))
         {
            return false;
         }
         while(states.length > 0)
         {
            if(!this.consumeMatchWork())
            {
               return false;
            }
            var state:Object = states.pop();
            var selectorIndex:int = int(state.selectorIndex);
            var ancestorIndex:int = int(state.ancestorIndex);
            if(selectorIndex == 0)
            {
               return true;
            }
            var part:Object = param1[selectorIndex];
            var targetIndex:int = selectorIndex - 1;
            if(part.combinator == "child")
            {
               if(ancestorIndex >= 0 && this.matchesSimple(param1[targetIndex],ancestors[ancestorIndex] as CanvasHtmlNode))
               {
                  if(!this.pushMatchState(states,targetIndex,ancestorIndex - 1))
                  {
                     return false;
                  }
               }
            }
            else
            {
               while(ancestorIndex >= 0)
               {
                  if(this.matchesSimple(param1[targetIndex],ancestors[ancestorIndex] as CanvasHtmlNode))
                  {
                     if(ancestorIndex > 0 && !this.pushMatchState(states,selectorIndex,ancestorIndex - 1))
                     {
                        return false;
                     }
                     if(!this.pushMatchState(states,targetIndex,ancestorIndex - 1))
                     {
                        return false;
                     }
                     break;
                  }
                  if(this.matchWorkExceeded)
                  {
                     return false;
                  }
                  ancestorIndex--;
               }
            }
         }
         return false;
      }

      private function pushMatchState(param1:Array, param2:int, param3:int) : Boolean
      {
         if(!this.consumeMatchWork())
         {
            return false;
         }
         param1.push({"selectorIndex":param2,"ancestorIndex":param3});
         return true;
      }

      private function matchesSimple(param1:Object, param2:CanvasHtmlNode) : Boolean
      {
         if(!this.consumeMatchWork())
         {
            return false;
         }
         if(param1 == null || param2 == null || param2.type != CanvasHtmlNode.ELEMENT)
         {
            return false;
         }
         var identity:Object = this.getIdentity(param2);
         if(identity == null)
         {
            return false;
         }
         if(param1.tag != null)
         {
            if(!this.consumeMatchWork(String(param1.tag).length) || param1.tag != param2.name)
            {
               return false;
            }
         }
         if(param1.id != null)
         {
            if(!this.consumeMatchWork(String(param1.id).length) || param1.id != identity.id)
            {
               return false;
            }
         }
         var required:String = null;
         for each(required in param1.classes)
         {
            if(!this.consumeMatchWork(required.length))
            {
               return false;
            }
            if(!identity.classes.hasOwnProperty("$" + required))
            {
               return false;
            }
         }
         return true;
      }

      private function getIdentity(param1:CanvasHtmlNode) : Object
      {
         var cached:Object = this.identityCache[param1];
         if(cached != null)
         {
            return cached;
         }
         var identifier:String = null;
         var classText:String = null;
         var attribute:CanvasHtmlAttribute = null;
         for each(attribute in param1.attributes)
         {
            if(!this.consumeMatchWork())
            {
               return null;
            }
            if(attribute.name == "id")
            {
               identifier = attribute.value;
            }
            else if(attribute.name == "class")
            {
               classText = attribute.value;
            }
         }
         var classes:Object = {};
         if(classText != null)
         {
            if(!this.consumeMatchWork(classText.length))
            {
               return null;
            }
            var values:Array = classText.split(" ");
            if(values.length > CanvasHtmlLimits.MAX_CLASSES_PER_ELEMENT)
            {
               this.matchWorkExceeded = true;
               return null;
            }
            var value:String = null;
            for each(value in values)
            {
               if(!this.consumeMatchWork())
               {
                  return null;
               }
               classes["$" + value] = true;
            }
         }
         cached = {"id":identifier,"classes":classes};
         this.identityCache[param1] = cached;
         return cached;
      }

      private function consumeMatchWork(param1:int = 1) : Boolean
      {
         if(param1 < 0 || this.matchWork > CanvasHtmlLimits.MAX_CSS_MATCH_WORK - param1)
         {
            this.matchWorkExceeded = true;
            return false;
         }
         this.matchWork += param1;
         return true;
      }
   }
}
