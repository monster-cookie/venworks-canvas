package
{
   public final class CanvasSvgTextParser
   {
      private var source:String;

      private var resource:String;

      private var position:int;

      private var failure:CanvasHtmlDiagnostic;

      private var elementCount:int;

      public function get diagnostic() : CanvasHtmlDiagnostic
      {
         return this.failure;
      }

      public function parse(param1:String, param2:String) : CanvasHtmlNode
      {
         this.source = param1 == null ? "" : param1;
         this.resource = param2;
         this.position = 0;
         this.failure = null;
         this.elementCount = 0;
         this.skipWhitespace();
         if(this.source.substr(this.position,5) == "<?xml")
         {
            if(!this.readDeclaration())
            {
               return null;
            }
            this.skipWhitespace();
         }
         var rootRecord:Object = this.readStartElement();
         if(rootRecord == null)
         {
            return null;
         }
         if(String(rootRecord.name) != "svg")
         {
            this.reject("unsupported-svg-element",int(rootRecord.offset));
            return null;
         }
         var root:CanvasHtmlNode = rootRecord.node as CanvasHtmlNode;
         this.elementCount = 1;
         if(!this.validateRoot(root) || Boolean(rootRecord.selfClosing))
         {
            if(this.failure == null)
            {
               this.reject("empty-svg",int(rootRecord.offset));
            }
            return null;
         }
         while(this.failure == null)
         {
            this.skipWhitespace();
            if(this.source.substr(this.position,2) == "</")
            {
               if(!this.readEndElement("svg"))
               {
                  return null;
               }
               break;
            }
            if(this.position >= this.source.length || this.source.charAt(this.position) != "<")
            {
               this.reject("invalid-svg-syntax",this.position);
               return null;
            }
            var pathRecord:Object = this.readStartElement();
            if(pathRecord == null)
            {
               return null;
            }
            if(String(pathRecord.name) != "path")
            {
               this.reject("unsupported-svg-element",int(pathRecord.offset));
               return null;
            }
            var path:CanvasHtmlNode = pathRecord.node as CanvasHtmlNode;
            if(path.getAttribute("d") == null || path.getAttribute("d").length == 0)
            {
               this.reject("invalid-svg-path",int(pathRecord.offset));
               return null;
            }
            this.elementCount++;
            if(this.elementCount > CanvasHtmlLimits.MAX_SVG_ELEMENTS)
            {
               this.reject("limit-exceeded",int(pathRecord.offset),"svg-elements");
               return null;
            }
            root.children.push(path);
            if(!Boolean(pathRecord.selfClosing))
            {
               this.skipWhitespace();
               if(!this.readEndElement("path"))
               {
                  return null;
               }
            }
         }
         this.skipWhitespace();
         if(this.failure != null || this.position != this.source.length)
         {
            if(this.failure == null)
            {
               this.reject("invalid-svg-syntax",this.position);
            }
            return null;
         }
         if(root.children.length == 0)
         {
            this.reject("empty-svg",root.offset);
            return null;
         }
         return root;
      }

      private function readDeclaration() : Boolean
      {
         var start:int = this.position;
         this.position += 5;
         if(!this.skipWhitespace())
         {
            return this.reject("invalid-svg-declaration",start);
         }
         var values:Object = {};
         while(this.position < this.source.length)
         {
            if(this.source.substr(this.position,2) == "?>")
            {
               this.position += 2;
               if(values["$version"] != "1.0" || String(values["$encoding"]).toLowerCase() != "utf-8")
               {
                  return this.reject("invalid-svg-declaration",start);
               }
               return true;
            }
            var nameOffset:int = this.position;
            var name:String = this.readName();
            if(name == null || name != "version" && name != "encoding" || values.hasOwnProperty("$" + name))
            {
               return this.reject("invalid-svg-declaration",nameOffset);
            }
            this.skipWhitespace();
            if(this.position >= this.source.length || this.source.charAt(this.position) != "=")
            {
               return this.reject("invalid-svg-declaration",this.position);
            }
            this.position++;
            this.skipWhitespace();
            var valueRecord:Object = this.readAttributeValue("invalid-svg-declaration");
            if(valueRecord == null)
            {
               return false;
            }
            values["$" + name] = String(valueRecord.value);
            var hadWhitespace:Boolean = this.skipWhitespace();
            if(this.source.substr(this.position,2) != "?>" && !hadWhitespace)
            {
               return this.reject("invalid-svg-declaration",this.position);
            }
         }
         return this.reject("invalid-svg-declaration",start);
      }

      private function readStartElement() : Object
      {
         var start:int = this.position;
         if(this.position >= this.source.length || this.source.charAt(this.position) != "<" || this.source.substr(this.position,2) == "</" || this.source.substr(this.position,2) == "<?" || this.source.substr(this.position,2) == "<!")
         {
            this.reject("invalid-svg-syntax",start);
            return null;
         }
         this.position++;
         var name:String = this.readName();
         if(name == null)
         {
            this.reject("invalid-svg-syntax",start);
            return null;
         }
         if(name != "svg" && name != "path")
         {
            this.reject("unsupported-svg-element",start);
            return null;
         }
         var node:CanvasHtmlNode = new CanvasHtmlNode(CanvasHtmlNode.ELEMENT,start);
         node.name = name;
         node.resource = this.resource;
         var names:Object = {};
         var hadWhitespace:Boolean = this.skipWhitespace();
         while(this.position < this.source.length)
         {
            if(this.source.substr(this.position,2) == "/>")
            {
               this.position += 2;
               return {"name":name,"node":node,"selfClosing":true,"offset":start};
            }
            if(this.source.charAt(this.position) == ">")
            {
               this.position++;
               return {"name":name,"node":node,"selfClosing":false,"offset":start};
            }
            if(!hadWhitespace)
            {
               this.reject("invalid-svg-syntax",this.position);
               return null;
            }
            var attributeOffset:int = this.position;
            var rawName:String = this.readName();
            if(rawName == null)
            {
               this.reject("invalid-svg-syntax",attributeOffset);
               return null;
            }
            var normalizedName:String = rawName == "viewBox" ? "viewbox" : rawName;
            if(!this.isAllowedAttribute(name,rawName) || names.hasOwnProperty("$" + normalizedName))
            {
               this.reject("unsupported-svg-attribute",attributeOffset);
               return null;
            }
            if(node.attributes.length >= CanvasHtmlLimits.MAX_ATTRIBUTES_PER_ELEMENT)
            {
               this.reject("limit-exceeded",attributeOffset,"attributes-per-element");
               return null;
            }
            names["$" + normalizedName] = true;
            this.skipWhitespace();
            if(this.position >= this.source.length || this.source.charAt(this.position) != "=")
            {
               this.reject("invalid-svg-syntax",this.position);
               return null;
            }
            this.position++;
            this.skipWhitespace();
            var valueRecord:Object = this.readAttributeValue("invalid-svg-syntax");
            if(valueRecord == null)
            {
               return null;
            }
            node.attributes.push(new CanvasHtmlAttribute(normalizedName,String(valueRecord.value),attributeOffset,int(valueRecord.offset)));
            hadWhitespace = this.skipWhitespace();
         }
         this.reject("invalid-svg-syntax",start);
         return null;
      }

      private function readEndElement(param1:String) : Boolean
      {
         var start:int = this.position;
         if(this.source.substr(this.position,2) != "</")
         {
            return this.reject("invalid-svg-syntax",start);
         }
         this.position += 2;
         var name:String = this.readName();
         this.skipWhitespace();
         if(name != param1 || this.position >= this.source.length || this.source.charAt(this.position) != ">")
         {
            return this.reject("invalid-svg-syntax",start);
         }
         this.position++;
         return true;
      }

      private function readAttributeValue(param1:String) : Object
      {
         if(this.position >= this.source.length)
         {
            this.reject(param1,this.position);
            return null;
         }
         var quote:String = this.source.charAt(this.position);
         if(quote != "\"" && quote != "'")
         {
            this.reject(param1,this.position);
            return null;
         }
         this.position++;
         var start:int = this.position;
         while(this.position < this.source.length && this.source.charAt(this.position) != quote)
         {
            var character:String = this.source.charAt(this.position);
            if(character == "<" || character == "&" || this.position - start >= CanvasHtmlLimits.MAX_STRING_CODE_UNITS)
            {
               this.reject(param1,this.position);
               return null;
            }
            this.position++;
         }
         if(this.position >= this.source.length)
         {
            this.reject(param1,start);
            return null;
         }
         var value:String = this.source.substring(start,this.position);
         this.position++;
         return {"value":value,"offset":start};
      }

      private function validateRoot(param1:CanvasHtmlNode) : Boolean
      {
         var viewbox:CanvasHtmlAttribute = this.findAttribute(param1,"viewbox");
         if(viewbox == null)
         {
            return this.reject("invalid-svg-viewbox",param1.offset);
         }
         var normalized:String = this.normalizeViewbox(viewbox.value);
         if(normalized == null)
         {
            return this.reject("invalid-svg-viewbox",viewbox.valueOffset);
         }
         viewbox.value = normalized;
         var namespaceValue:String = param1.getAttribute("xmlns");
         if(namespaceValue != null && !this.isSvgNamespace(namespaceValue))
         {
            return this.reject("invalid-svg-namespace",param1.getAttributeValueOffset("xmlns"));
         }
         return true;
      }

      private function isSvgNamespace(param1:String) : Boolean
      {
         return param1 != null && param1.substr(0,4) == "http" && param1.substr(4) == "://www.w3.org/2000/svg";
      }

      private function normalizeViewbox(param1:String) : String
      {
         if(param1 == null || param1.length == 0)
         {
            return null;
         }
         var matchPattern:RegExp = /[-+]?(?:[0-9]*\.[0-9]+|[0-9]+\.?)(?:[eE][-+]?[0-9]+)?/g;
         var removalPattern:RegExp = /[-+]?(?:[0-9]*\.[0-9]+|[0-9]+\.?)(?:[eE][-+]?[0-9]+)?/g;
         var values:Array = param1.match(matchPattern);
         var remainder:String = param1.replace(removalPattern,"").replace(/[\s,]+/g,"");
         if(remainder.length != 0 || values == null || values.length != 4)
         {
            return null;
         }
         var numbers:Array = [];
         var value:String = null;
         for each(value in values)
         {
            var number:Number = Number(value);
            if(!isFinite(number) || Math.abs(number) > CanvasHtmlLimits.MAX_SVG_COORDINATE)
            {
               return null;
            }
            numbers.push(number);
         }
         if(Number(numbers[2]) <= 0 || Number(numbers[3]) <= 0 || Math.abs(Number(numbers[0]) + Number(numbers[2])) > CanvasHtmlLimits.MAX_SVG_COORDINATE || Math.abs(Number(numbers[1]) + Number(numbers[3])) > CanvasHtmlLimits.MAX_SVG_COORDINATE)
         {
            return null;
         }
         return numbers.join(" ");
      }

      private function findAttribute(param1:CanvasHtmlNode, param2:String) : CanvasHtmlAttribute
      {
         var attribute:CanvasHtmlAttribute = null;
         for each(attribute in param1.attributes)
         {
            if(attribute.name == param2)
            {
               return attribute;
            }
         }
         return null;
      }

      private function isAllowedAttribute(param1:String, param2:String) : Boolean
      {
         if(param1 == "svg")
         {
            return param2 == "viewBox" || param2 == "viewbox" || param2 == "xmlns";
         }
         if(param1 == "path")
         {
            return param2 == "d" || param2 == "fill" || param2 == "stroke" || param2 == "stroke-width";
         }
         return false;
      }

      private function readName() : String
      {
         var start:int = this.position;
         if(this.position >= this.source.length || !this.isNameStart(this.source.charCodeAt(this.position)))
         {
            return null;
         }
         this.position++;
         while(this.position < this.source.length && this.isNameCharacter(this.source.charCodeAt(this.position)))
         {
            this.position++;
         }
         return this.source.substring(start,this.position);
      }

      private function skipWhitespace() : Boolean
      {
         var start:int = this.position;
         while(this.position < this.source.length)
         {
            var code:int = this.source.charCodeAt(this.position);
            if(code != 9 && code != 10 && code != 13 && code != 32)
            {
               break;
            }
            this.position++;
         }
         return this.position > start;
      }

      private function isNameStart(param1:int) : Boolean
      {
         return param1 >= 65 && param1 <= 90 || param1 >= 97 && param1 <= 122;
      }

      private function isNameCharacter(param1:int) : Boolean
      {
         return this.isNameStart(param1) || param1 >= 48 && param1 <= 57 || param1 == 45;
      }

      private function reject(param1:String, param2:int, param3:String = null) : Boolean
      {
         if(this.failure == null)
         {
            this.failure = new CanvasHtmlDiagnostic("asset",param1,this.resource,CanvasUtf8Decoder.byteOffset(this.source,param2),param3);
         }
         return false;
      }
   }
}
