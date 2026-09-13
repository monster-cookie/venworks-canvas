package
{
   public final class CanvasHtmlTokenizer
   {
      private static const DOCTYPE_SOURCE:String = "<!doctype html>";

      private var source:String;

      private var resource:String;

      private var position:int;

      private var emittedTokenCount:int;

      private var failure:CanvasHtmlDiagnostic;

      public function CanvasHtmlTokenizer(param1:String, param2:String)
      {
         this.source = param1 == null ? "" : param1;
         this.resource = param2;
      }

      public function get diagnostic() : CanvasHtmlDiagnostic
      {
         return this.failure;
      }

      public function get tokenCount() : int
      {
         return this.emittedTokenCount;
      }

      public function nextToken() : CanvasHtmlToken
      {
         if(this.failure != null || this.position >= this.source.length)
         {
            return null;
         }
         if(this.position == 0)
         {
            return this.readDoctype();
         }
         var current:String = this.source.charAt(this.position);
         if(current == "<")
         {
            if(this.source.substr(this.position,4) == "<!--" || this.source.substr(this.position,2) == "<?" || this.source.substr(this.position,9) == "<![CDATA[")
            {
               this.reject("unsupported-feature",this.position);
               return null;
            }
            if(this.source.substr(this.position,2) == "</")
            {
               return this.readEndTag();
            }
            if(this.source.substr(this.position,2) == "<!")
            {
               this.reject("malformed-syntax",this.position);
               return null;
            }
            return this.readStartTag();
         }
         if(current == "&")
         {
            return this.readCharacterReferenceToken();
         }
         return this.readText();
      }

      private function readDoctype() : CanvasHtmlToken
      {
         if(this.source.substr(0,4) == "<!--" || this.source.substr(0,2) == "<?" || this.source.substr(0,9) == "<![CDATA[")
         {
            this.reject("unsupported-feature",0);
            return null;
         }
         if(this.source.substr(0,DOCTYPE_SOURCE.length) != DOCTYPE_SOURCE)
         {
            this.reject("malformed-syntax",0);
            return null;
         }
         this.position = DOCTYPE_SOURCE.length;
         if(!this.countToken(0))
         {
            return null;
         }
         return new CanvasHtmlToken(CanvasHtmlToken.DOCTYPE,0);
      }

      private function readStartTag() : CanvasHtmlToken
      {
         var start:int = this.position;
         this.position++;
         var nameOffset:int = this.position;
         var name:String = this.readName();
         if(name == null)
         {
            this.reject("malformed-syntax",nameOffset);
            return null;
         }
         if(!this.countToken(start))
         {
            return null;
         }
         var token:CanvasHtmlToken = new CanvasHtmlToken(CanvasHtmlToken.START_TAG,start);
         token.name = name;
         var names:Object = {};
         var hadWhitespace:Boolean = this.skipWhitespace();
         while(this.position < this.source.length && this.source.charAt(this.position) != ">")
         {
            if(!hadWhitespace || this.source.charAt(this.position) == "/")
            {
               this.reject("malformed-syntax",this.position);
               return null;
            }
            var attributeOffset:int = this.position;
            var attributeName:String = this.readName();
            if(attributeName == null)
            {
               this.reject("malformed-syntax",attributeOffset);
               return null;
            }
            if(names.hasOwnProperty(attributeName))
            {
               this.reject("malformed-syntax",attributeOffset);
               return null;
            }
            names[attributeName] = true;
            if(token.attributes.length >= CanvasHtmlLimits.MAX_ATTRIBUTES_PER_ELEMENT)
            {
               this.reject("limit-exceeded",attributeOffset,"attributes-per-element");
               return null;
            }
            this.skipWhitespace();
            if(this.position >= this.source.length || this.source.charAt(this.position) != "=")
            {
               this.reject("malformed-syntax",this.position);
               return null;
            }
            this.position++;
            this.skipWhitespace();
            if(this.position >= this.source.length || this.source.charAt(this.position) != "\"")
            {
               this.reject("malformed-syntax",this.position);
               return null;
            }
            this.position++;
            var attributeValue:String = this.readAttributeValue();
            if(attributeValue == null)
            {
               return null;
            }
            token.attributes.push(new CanvasHtmlAttribute(attributeName,attributeValue,attributeOffset));
            hadWhitespace = this.skipWhitespace();
         }
         if(this.position >= this.source.length || this.source.charAt(this.position) != ">")
         {
            this.reject("malformed-syntax",start);
            return null;
         }
         this.position++;
         return token;
      }

      private function readEndTag() : CanvasHtmlToken
      {
         var start:int = this.position;
         this.position += 2;
         var nameOffset:int = this.position;
         var name:String = this.readName();
         if(name == null)
         {
            this.reject("malformed-syntax",nameOffset);
            return null;
         }
         this.skipWhitespace();
         if(this.position >= this.source.length || this.source.charAt(this.position) != ">")
         {
            this.reject("malformed-syntax",this.position);
            return null;
         }
         this.position++;
         if(!this.countToken(start))
         {
            return null;
         }
         var token:CanvasHtmlToken = new CanvasHtmlToken(CanvasHtmlToken.END_TAG,start);
         token.name = name;
         return token;
      }

      private function readText() : CanvasHtmlToken
      {
         var start:int = this.position;
         while(this.position < this.source.length && this.source.charAt(this.position) != "<" && this.source.charAt(this.position) != "&")
         {
            this.position++;
         }
         var value:String = this.source.substring(start,this.position);
         if(value.length > CanvasHtmlLimits.MAX_STRING_CODE_UNITS)
         {
            this.reject("limit-exceeded",start,"string-code-units");
            return null;
         }
         if(!this.countToken(start))
         {
            return null;
         }
         var token:CanvasHtmlToken = new CanvasHtmlToken(CanvasHtmlToken.TEXT,start);
         token.text = value;
         return token;
      }

      private function readCharacterReferenceToken() : CanvasHtmlToken
      {
         var start:int = this.position;
         var value:String = this.readCharacterReference();
         if(value == null)
         {
            return null;
         }
         var token:CanvasHtmlToken = new CanvasHtmlToken(CanvasHtmlToken.CHARACTER_REFERENCE,start);
         token.text = value;
         return token;
      }

      private function readAttributeValue() : String
      {
         var chunks:Array = [];
         var valueLength:int = 0;
         var literalStart:int = this.position;
         while(this.position < this.source.length && this.source.charAt(this.position) != "\"")
         {
            var current:String = this.source.charAt(this.position);
            if(current == "<")
            {
               this.reject("malformed-syntax",this.position);
               return null;
            }
            if(current == "&")
            {
               if(this.position > literalStart)
               {
                  var literal:String = this.source.substring(literalStart,this.position);
                  chunks.push(literal);
                  valueLength += literal.length;
               }
               var decoded:String = this.readCharacterReference();
               if(decoded == null)
               {
                  return null;
               }
               chunks.push(decoded);
               valueLength += decoded.length;
               literalStart = this.position;
            }
            else
            {
               this.position++;
            }
            if(valueLength + this.position - literalStart > CanvasHtmlLimits.MAX_STRING_CODE_UNITS)
            {
               this.reject("limit-exceeded",literalStart,"string-code-units");
               return null;
            }
         }
         if(this.position >= this.source.length)
         {
            this.reject("malformed-syntax",literalStart);
            return null;
         }
         if(this.position > literalStart)
         {
            literal = this.source.substring(literalStart,this.position);
            chunks.push(literal);
            valueLength += literal.length;
         }
         if(valueLength > CanvasHtmlLimits.MAX_STRING_CODE_UNITS)
         {
            this.reject("limit-exceeded",literalStart,"string-code-units");
            return null;
         }
         this.position++;
         return chunks.join("");
      }

      private function readCharacterReference() : String
      {
         var start:int = this.position;
         var semicolon:int = this.source.indexOf(";",start + 1);
         if(semicolon < 0 || semicolon - start > 6)
         {
            this.reject("malformed-syntax",start);
            return null;
         }
         var name:String = this.source.substring(start + 1,semicolon);
         var value:String = null;
         if(name == "amp")
         {
            value = "&";
         }
         else if(name == "apos")
         {
            value = "'";
         }
         else if(name == "gt")
         {
            value = ">";
         }
         else if(name == "lt")
         {
            value = "<";
         }
         else if(name == "quot")
         {
            value = "\"";
         }
         else
         {
            this.reject("malformed-syntax",start);
            return null;
         }
         this.position = semicolon + 1;
         if(!this.countToken(start))
         {
            return null;
         }
         return value;
      }

      private function readName() : String
      {
         var start:int = this.position;
         if(this.position >= this.source.length || !this.isLowerLetter(this.source.charCodeAt(this.position)))
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
         while(this.position < this.source.length && this.isWhitespace(this.source.charCodeAt(this.position)))
         {
            this.position++;
         }
         return this.position > start;
      }

      private function countToken(param1:int) : Boolean
      {
         this.emittedTokenCount++;
         if(this.emittedTokenCount > CanvasHtmlLimits.MAX_HTML_TOKENS)
         {
            this.reject("limit-exceeded",param1,"html-tokens");
            return false;
         }
         return true;
      }

      private function reject(param1:String, param2:int, param3:String = null) : void
      {
         if(this.failure == null)
         {
            this.failure = new CanvasHtmlDiagnostic("parse",param1,this.resource,CanvasUtf8Decoder.byteOffset(this.source,param2),param3);
         }
      }

      private function isLowerLetter(param1:int) : Boolean
      {
         return param1 >= 97 && param1 <= 122;
      }

      private function isNameCharacter(param1:int) : Boolean
      {
         return this.isLowerLetter(param1) || param1 >= 48 && param1 <= 57 || param1 == 45;
      }

      private function isWhitespace(param1:int) : Boolean
      {
         return param1 == 32 || param1 == 9 || param1 == 10 || param1 == 13;
      }
   }
}
