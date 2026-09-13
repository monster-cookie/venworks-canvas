package
{
   public final class CanvasCssParser
   {
      private var rules:Array;

      private var ruleCount:int;

      private var sourceOrder:int;

      private var failure:CanvasHtmlDiagnostic;

      private var currentResource:String;

      private var currentSource:String;

      private var importCount:int;

      public function parse(param1:CanvasHtmlLoadResult) : CanvasCssParseResult
      {
         this.rules = [];
         this.ruleCount = 0;
         this.sourceOrder = 0;
         this.failure = null;
         this.importCount = 0;
         if(param1 == null || !param1.success || param1.entryDocument == null)
         {
            return new CanvasCssParseResult(false,null,new CanvasHtmlDiagnostic("style","missing-document",null));
         }
         var resources:Object = {};
         var resource:CanvasHtmlResource = null;
         for each(resource in param1.resources)
         {
            resources[resource.path] = resource;
         }
         for each(resource in param1.resources)
         {
            if(resource.document != null && !this.parseDocument(resource.document,resources))
            {
               return new CanvasCssParseResult(false,null,this.failure);
            }
         }
         return new CanvasCssParseResult(true,new CanvasCssCascade(this.rules),null);
      }

      private function parseDocument(param1:CanvasHtmlDocument, param2:Object) : Boolean
      {
         var head:CanvasHtmlNode = null;
         var child:CanvasHtmlNode = null;
         for each(child in param1.root.children)
         {
            if(child.type == CanvasHtmlNode.ELEMENT && child.name == "head")
            {
               head = child;
               break;
            }
         }
         if(head == null)
         {
            return this.reject("missing-head",param1.resource,0);
         }
         for each(child in head.children)
         {
            if(child.name == "style")
            {
               var inlineText:String = child.children.length == 0 ? "" : CanvasHtmlNode(child.children[0]).text;
               if(!this.parseSource(inlineText,param1.resource,param2,0,[]))
               {
                  return false;
               }
            }
            else if(child.name == "link")
            {
               var resolved:String = CanvasHtmlPath.resolve(param1.resource,child.getAttribute("href"));
               var linked:CanvasHtmlResource = resolved == null ? null : param2[resolved] as CanvasHtmlResource;
               if(linked == null || linked.kind != "css")
               {
                  return this.reject("resource-unavailable",param1.resource,child.referenceOffset,"asset");
               }
               if(!this.parseSource(linked.text,linked.path,param2,1,[linked.path]))
               {
                  return false;
               }
            }
         }
         return true;
      }

      private function parseSource(param1:String, param2:String, param3:Object, param4:int, param5:Array) : Boolean
      {
         this.currentResource = param2;
         this.currentSource = param1 == null ? "" : param1;
         var imports:CanvasCssImportResult = new CanvasCssImportScanner().scan(this.currentSource,param2);
         if(!imports.success)
         {
            this.failure = imports.diagnostic;
            return false;
         }
         var imported:Object = null;
         for each(imported in imports.imports)
         {
            this.importCount++;
            if(this.importCount > CanvasHtmlLimits.MAX_CSS_IMPORTS)
            {
               return this.reject("limit-exceeded",param2,int(imported.offset),"style","css-import-count");
            }
            var resolved:String = CanvasHtmlPath.resolve(param2,String(imported.path));
            var resource:CanvasHtmlResource = resolved == null ? null : param3[resolved] as CanvasHtmlResource;
            if(resource == null || resource.kind != "css")
            {
               return this.reject("resource-unavailable",param2,int(imported.offset),"asset");
            }
            if(param5.indexOf(resolved) >= 0)
            {
               return this.reject("cycle",param2,int(imported.offset),"style","css-import-cycle");
            }
            if(param4 + 1 > CanvasHtmlLimits.MAX_CSS_IMPORT_DEPTH)
            {
               return this.reject("limit-exceeded",param2,int(imported.offset),"style","css-import-depth");
            }
            if(!this.parseSource(resource.text,resource.path,param3,param4 + 1,param5.concat([resolved])))
            {
               return false;
            }
            this.currentResource = param2;
            this.currentSource = param1 == null ? "" : param1;
         }
         this.currentResource = param2;
         this.currentSource = param1 == null ? "" : param1;
         var source:String = imports.source;
         var index:int = imports.ruleOffset;
         var length:int = source.length;
         while(index < length)
         {
            index = this.skipWhitespace(source,index);
            if(index >= length)
            {
               break;
            }
            var selectorStart:int = index;
            var openIndex:int = source.indexOf("{",index);
            var prematureClose:int = source.indexOf("}",index);
            if(openIndex < 0 || prematureClose >= 0 && prematureClose < openIndex)
            {
               return this.reject("malformed-syntax",param2,selectorStart);
            }
            var closeIndex:int = source.indexOf("}",openIndex + 1);
            if(closeIndex < 0 || source.indexOf("{",openIndex + 1) >= 0 && source.indexOf("{",openIndex + 1) < closeIndex)
            {
               return this.reject("malformed-syntax",param2,openIndex);
            }
            var selectors:Array = this.parseSelectors(source.substring(selectorStart,openIndex),selectorStart);
            if(selectors == null)
            {
               return false;
            }
            var declarations:Array = this.parseDeclarations(source.substring(openIndex + 1,closeIndex),openIndex + 1);
            if(declarations == null)
            {
               return false;
            }
            var selector:Object = null;
            for each(selector in selectors)
            {
               this.ruleCount++;
               if(this.ruleCount > CanvasHtmlLimits.MAX_CSS_RULES)
               {
                  return this.reject("limit-exceeded",param2,selectorStart,"style","css-rule-count");
               }
               this.sourceOrder++;
               this.rules.push({"selector":selector.parts,"specificity":selector.specificity,"order":this.sourceOrder,"declarations":declarations});
            }
            index = closeIndex + 1;
         }
         return true;
      }

      private function parseSelectors(param1:String, param2:int) : Array
      {
         var rawSelectors:Array = param1.split(",");
         if(param1.length == 0 || param1.length > CanvasHtmlLimits.MAX_CSS_SELECTOR_CODE_UNITS || rawSelectors.length == 0 || rawSelectors.length > CanvasHtmlLimits.MAX_CSS_SELECTORS_PER_RULE)
         {
            this.reject("limit-exceeded",this.currentResource,param2,"style","selectors-per-rule");
            return null;
         }
         var result:Array = [];
         var seen:Object = {};
         var raw:String = null;
         for each(raw in rawSelectors)
         {
            var selector:Object = this.parseSelector(CanvasCssValue.trim(raw),param2);
            if(selector == null)
            {
               return null;
            }
            var key:String = this.selectorKey(selector.parts);
            if(seen.hasOwnProperty(key))
            {
               this.reject("duplicate-selector",this.currentResource,param2,"style");
               return null;
            }
            seen[key] = true;
            result.push(selector);
         }
         return result;
      }

      private function parseSelector(param1:String, param2:int) : Object
      {
         if(param1.length == 0)
         {
            this.reject("malformed-syntax",this.currentResource,param2);
            return null;
         }
         var parts:Array = [];
         var index:int = 0;
         var pendingCombinator:String = null;
         var specificity:int = 0;
         while(index < param1.length)
         {
            var spaceStart:int = index;
            index = this.skipWhitespace(param1,index);
            if(index > spaceStart && parts.length > 0 && pendingCombinator == null)
            {
               pendingCombinator = "descendant";
            }
            if(index < param1.length && param1.charAt(index) == ">")
            {
               if(parts.length == 0 || pendingCombinator == "child")
               {
                  this.reject("malformed-syntax",this.currentResource,param2 + index);
                  return null;
               }
               pendingCombinator = "child";
               index = this.skipWhitespace(param1,index + 1);
               if(index >= param1.length)
               {
                  this.reject("malformed-syntax",this.currentResource,param2 + index);
                  return null;
               }
            }
            var simple:Object = {"tag":null,"id":null,"classes":[],"combinator":parts.length == 0 ? null : pendingCombinator};
            var qualifierCount:int = 0;
            var classNames:Object = {};
            pendingCombinator = null;
            if(this.isIdentifierStart(param1.charCodeAt(index)))
            {
               var tagResult:Object = this.readIdentifier(param1,index);
               simple.tag = tagResult.value;
               index = int(tagResult.next);
               qualifierCount++;
               if(String(simple.tag).length > CanvasHtmlLimits.MAX_IDENTIFIER_LENGTH || !this.isElementName(String(simple.tag)))
               {
                  this.reject("unsupported-selector",this.currentResource,param2 + index);
                  return null;
               }
               specificity += 1;
            }
            while(index < param1.length && (param1.charAt(index) == "." || param1.charAt(index) == "#"))
            {
               var marker:String = param1.charAt(index);
               index++;
               if(index >= param1.length || !this.isIdentifierStart(param1.charCodeAt(index)))
               {
                  this.reject("malformed-syntax",this.currentResource,param2 + index);
                  return null;
               }
               var nameResult:Object = this.readIdentifier(param1,index);
               index = int(nameResult.next);
               if(String(nameResult.value).length > CanvasHtmlLimits.MAX_IDENTIFIER_LENGTH)
               {
                  this.reject("limit-exceeded",this.currentResource,param2 + index,"style","selector-identifier-length");
                  return null;
               }
               qualifierCount++;
               if(qualifierCount > CanvasHtmlLimits.MAX_CSS_QUALIFIERS_PER_PART)
               {
                  this.reject("limit-exceeded",this.currentResource,param2 + index,"style","selector-qualifiers");
                  return null;
               }
               if(marker == "#")
               {
                  if(simple.id != null)
                  {
                     this.reject("unsupported-selector",this.currentResource,param2 + index);
                     return null;
                  }
                  simple.id = nameResult.value;
                  specificity += 10000;
               }
               else
               {
                  if(classNames.hasOwnProperty(String(nameResult.value)))
                  {
                     this.reject("duplicate-selector-qualifier",this.currentResource,param2 + index);
                     return null;
                  }
                  classNames[String(nameResult.value)] = true;
                  simple.classes.push(nameResult.value);
                  specificity += 100;
               }
            }
            if(simple.tag == null && simple.id == null && simple.classes.length == 0 || parts.length > 0 && simple.combinator == null)
            {
               this.reject("malformed-syntax",this.currentResource,param2 + index);
               return null;
            }
            parts.push(simple);
            if(parts.length > CanvasHtmlLimits.MAX_CSS_SELECTOR_PARTS)
            {
               this.reject("limit-exceeded",this.currentResource,param2 + index,"style","selector-parts");
               return null;
            }
            if(index < param1.length && !this.isWhitespace(param1.charCodeAt(index)) && param1.charAt(index) != ">")
            {
               this.reject("unsupported-selector",this.currentResource,param2 + index);
               return null;
            }
         }
         return {"parts":parts,"specificity":specificity};
      }

      private function selectorKey(param1:Array) : String
      {
         var result:String = "";
         var part:Object = null;
         for each(part in param1)
         {
            var classes:Array = (part.classes as Array).concat();
            classes.sort();
            result += "|" + String(part.combinator) + ":" + String(part.tag) + "#" + String(part.id) + "." + classes.join(".");
         }
         return result;
      }

      private function parseDeclarations(param1:String, param2:int) : Array
      {
         var result:Array = [];
         var values:Object = {};
         var index:int = 0;
         while(index < param1.length)
         {
            index = this.skipWhitespace(param1,index);
            while(index < param1.length && param1.charAt(index) == ";")
            {
               index = this.skipWhitespace(param1,index + 1);
            }
            if(index >= param1.length)
            {
               break;
            }
            var nameStart:int = index;
            while(index < param1.length && (param1.charCodeAt(index) >= 97 && param1.charCodeAt(index) <= 122 || param1.charAt(index) == "-"))
            {
               index++;
            }
            var propertyName:String = param1.substring(nameStart,index);
            index = this.skipWhitespace(param1,index);
            if(propertyName.length == 0 || index >= param1.length || param1.charAt(index) != ":")
            {
               this.reject("malformed-syntax",this.currentResource,param2 + nameStart);
               return null;
            }
            var valueStart:int = index + 1;
            var valueEnd:int = param1.indexOf(";",valueStart);
            if(valueEnd < 0)
            {
               valueEnd = param1.length;
            }
            var propertyValue:String = CanvasCssValue.trim(param1.substring(valueStart,valueEnd));
            if(propertyValue.length == 0 || propertyValue.indexOf("!") >= 0 || !this.addDeclaration(values,propertyName,propertyValue))
            {
               this.reject("unsupported-value",this.currentResource,param2 + valueStart);
               return null;
            }
            index = valueEnd < param1.length ? valueEnd + 1 : valueEnd;
         }
         var declarationName:String = null;
         for(declarationName in values)
         {
            result.push({"name":declarationName,"value":values[declarationName]});
         }
         if(result.length == 0)
         {
            this.reject("malformed-syntax",this.currentResource,param2);
            return null;
         }
         if(result.length > CanvasHtmlLimits.MAX_CSS_DECLARATIONS_PER_RULE)
         {
            this.reject("limit-exceeded",this.currentResource,param2,"style","declarations-per-rule");
            return null;
         }
         return result;
      }

      private function addDeclaration(param1:Object, param2:String, param3:String) : Boolean
      {
         if(param2 == "display")
         {
            if(param3 != "block" && param3 != "inline" && param3 != "none" && param3 != "flex")
            {
               return false;
            }
         }
         else if(param2 == "flex-direction")
         {
            if(param3 != "row" && param3 != "column")
            {
               return false;
            }
         }
         else if(param2 == "width")
         {
            if(CanvasCssValue.parseLength(param3,true,true,false) == null)
            {
               return false;
            }
         }
         else if(param2 == "height")
         {
            if(CanvasCssValue.parseLength(param3,true,false,false) == null)
            {
               return false;
            }
         }
         else if(param2 == "margin" || param2 == "padding")
         {
            return this.addBoxShorthand(param1,param2,param3,param2 == "margin");
         }
         else if(param2 == "margin-top" || param2 == "margin-right" || param2 == "margin-bottom" || param2 == "margin-left")
         {
            if(CanvasCssValue.parseLength(param3,false,false,true) == null)
            {
               return false;
            }
         }
         else if(param2 == "padding-top" || param2 == "padding-right" || param2 == "padding-bottom" || param2 == "padding-left" || param2 == "gap" || param2 == "border-width")
         {
            if(CanvasCssValue.parseLength(param3,false,false,false) == null)
            {
               return false;
            }
         }
         else if(param2 == "color" || param2 == "background-color" || param2 == "border-color")
         {
            if(CanvasCssValue.parseColor(param3) == null)
            {
               return false;
            }
         }
         else if(param2 == "border-style")
         {
            if(param3 != "none" && param3 != "solid")
            {
               return false;
            }
         }
         else if(param2 == "font-family")
         {
            if(!CanvasCssValue.isFontFamily(param3))
            {
               return false;
            }
         }
         else if(param2 == "font-size")
         {
            var fontSize:Object = CanvasCssValue.parseLength(param3,false,false,false);
            if(fontSize == null || Number(fontSize.value) < 6 || Number(fontSize.value) > 256)
            {
               return false;
            }
         }
         else if(param2 == "font-weight")
         {
            if(param3 != "normal" && param3 != "bold")
            {
               return false;
            }
         }
         else if(param2 == "text-align")
         {
            if(param3 != "left" && param3 != "center" && param3 != "right")
            {
               return false;
            }
         }
         else if(param2 == "line-height")
         {
            if(param3 != "normal" && CanvasCssValue.parseLength(param3,false,false,false) == null)
            {
               return false;
            }
         }
         else if(param2 == "overflow")
         {
            if(param3 != "visible" && param3 != "hidden")
            {
               return false;
            }
         }
         else if(param2 == "opacity")
         {
            if(!/^(?:0(?:\.[0-9]+)?|1(?:\.0+)?)$/.test(param3))
            {
               return false;
            }
         }
         else if(param2 == "position")
         {
            if(param3 != "static" && param3 != "relative" && param3 != "absolute")
            {
               return false;
            }
         }
         else if(param2 == "left" || param2 == "top")
         {
            if(CanvasCssValue.parseLength(param3,false,true,true) == null)
            {
               return false;
            }
         }
         else if(param2 == "z-index")
         {
            if(!/^-?(?:0|[1-9][0-9]*)$/.test(param3))
            {
               return false;
            }
            var zIndex:Number = Number(param3);
            if(!isFinite(zIndex) || zIndex < CanvasHtmlLimits.MIN_Z_INDEX || zIndex > CanvasHtmlLimits.MAX_Z_INDEX)
            {
               return false;
            }
         }
         else
         {
            return false;
         }
         param1[param2] = param3;
         return true;
      }

      private function addBoxShorthand(param1:Object, param2:String, param3:String, param4:Boolean) : Boolean
      {
         var parts:Array = param3.split(/\s+/);
         if(parts.length != 1 && parts.length != 2 && parts.length != 4)
         {
            return false;
         }
         var part:String = null;
         for each(part in parts)
         {
            if(CanvasCssValue.parseLength(part,false,false,param4) == null)
            {
               return false;
            }
         }
         var top:String = parts[0];
         var right:String = parts.length == 1 ? top : parts[1];
         var bottom:String = parts.length == 4 ? parts[2] : top;
         var left:String = parts.length == 4 ? parts[3] : right;
         param1[param2 + "-top"] = top;
         param1[param2 + "-right"] = right;
         param1[param2 + "-bottom"] = bottom;
         param1[param2 + "-left"] = left;
         return true;
      }

      private function readIdentifier(param1:String, param2:int) : Object
      {
         var index:int = param2 + 1;
         while(index < param1.length && this.isIdentifierCharacter(param1.charCodeAt(index)))
         {
            index++;
         }
         return {"value":param1.substring(param2,index),"next":index};
      }

      private function isElementName(param1:String) : Boolean
      {
         return param1 == "html" || param1 == "head" || param1 == "body" || param1 == "main" || param1 == "header" || param1 == "footer" || param1 == "section" || param1 == "div" || param1 == "span" || param1 == "h1" || param1 == "h2" || param1 == "h3" || param1 == "h4" || param1 == "h5" || param1 == "h6" || param1 == "p" || param1 == "br" || param1 == "hr" || param1 == "ul" || param1 == "ol" || param1 == "li" || param1 == "button" || param1 == "img" || param1 == "svg" || param1 == "path" || param1 == "vw-meter";
      }

      private function skipWhitespace(param1:String, param2:int) : int
      {
         while(param2 < param1.length && this.isWhitespace(param1.charCodeAt(param2)))
         {
            param2++;
         }
         return param2;
      }

      private function isIdentifierStart(param1:int) : Boolean
      {
         return param1 >= 97 && param1 <= 122;
      }

      private function isIdentifierCharacter(param1:int) : Boolean
      {
         return this.isIdentifierStart(param1) || param1 >= 48 && param1 <= 57 || param1 == 45;
      }

      private function isWhitespace(param1:int) : Boolean
      {
         return param1 == 9 || param1 == 10 || param1 == 12 || param1 == 13 || param1 == 32;
      }

      private function reject(param1:String, param2:String, param3:int, param4:String = "style", param5:String = null) : Boolean
      {
         if(this.failure == null)
         {
            var byteOffset:int = param3 < 0 || param2 != this.currentResource ? param3 : CanvasUtf8Decoder.byteOffset(this.currentSource,param3);
            this.failure = new CanvasHtmlDiagnostic(param4,param1,param2,byteOffset,param5);
         }
         return false;
      }
   }
}
