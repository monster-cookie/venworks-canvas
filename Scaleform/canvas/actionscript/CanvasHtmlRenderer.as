package
{
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.geom.Rectangle;
   import flash.text.TextField;
   import flash.text.TextFormat;

   public final class CanvasHtmlRenderer
   {
      private var stylesheet:CanvasCssCascade;

      private var resources:Object;

      private var viewportWidth:Number;

      private var viewportHeight:Number;

      private var failure:CanvasHtmlDiagnostic;

      private var svgCache:Object;

      private var svgWork:int;

      private var currentSvgResource:String;

      public function render(param1:CanvasHtmlNode, param2:CanvasCssCascade, param3:CanvasHtmlLoadResult, param4:Number, param5:Number) : CanvasHtmlRenderResult
      {
         this.stylesheet = param2;
         this.resources = {};
         this.viewportWidth = param4;
         this.viewportHeight = param5;
         this.failure = null;
         this.svgCache = {};
         this.svgWork = 0;
         this.currentSvgResource = null;
         if(param1 == null || param2 == null || param3 == null || !isFinite(param4) || !isFinite(param5) || param4 <= 0 || param5 <= 0)
         {
            return new CanvasHtmlRenderResult(false,null,0,0,new CanvasHtmlDiagnostic("render","invalid-input",param1 == null ? null : param1.resource));
         }
         var resource:CanvasHtmlResource = null;
         for each(resource in param3.resources)
         {
            this.resources[resource.path] = resource;
         }
         this.stylesheet.beginPass();
         var build:Object = this.buildTree(param1);
         if(build == null)
         {
            return new CanvasHtmlRenderResult(false,null,0,0,this.failure);
         }
         var boxes:Array = build.boxes as Array;
         var root:Object = build.root;
         if(!this.resolveWidths(boxes,root) || !this.measureLeaves(boxes) || !this.resolveHeights(boxes))
         {
            this.disposeDisplay(root == null ? null : root.sprite as Sprite);
            return new CanvasHtmlRenderResult(false,null,0,0,this.failure);
         }
         return new CanvasHtmlRenderResult(true,root.sprite as Sprite,Number(root.width),Number(root.height),null);
      }

      private function buildTree(param1:CanvasHtmlNode) : Object
      {
         var boxes:Array = [];
         var root:Object = null;
         var frames:Array = [{"node":param1,"parent":null,"ancestors":[]}];
         while(frames.length > 0)
         {
            var frame:Object = frames.pop();
            var node:CanvasHtmlNode = frame.node as CanvasHtmlNode;
            var parent:Object = frame.parent;
            var ancestors:Array = frame.ancestors as Array;
            var style:Object = node.type == CanvasHtmlNode.TEXT ? this.stylesheet.inheritedStyle(parent == null ? null : parent.style) : this.stylesheet.computeStyle(node,ancestors,parent == null ? null : parent.style);
            if(style == null || this.stylesheet.exceededMatchWork)
            {
               this.disposeDisplay(root == null ? null : root.sprite as Sprite);
               this.reject("limit-exceeded",node.resource,"style");
               return null;
            }
            if(node.type == CanvasHtmlNode.TEXT)
            {
               style["display"] = "inline";
            }
            if(style["display"] == "none")
            {
               continue;
            }
            var sprite:Sprite = new Sprite();
            sprite.mouseEnabled = false;
            sprite.mouseChildren = false;
            var box:Object = {
               "node":node,
               "style":style,
               "sprite":sprite,
               "parent":parent,
               "children":[],
               "available":0,
               "assignedWidth":-1,
               "width":0,
               "height":0,
               "innerWidth":0,
               "contentHeight":0,
               "marginTop":0,
               "marginRight":0,
               "marginBottom":0,
               "marginLeft":0,
               "paddingTop":0,
               "paddingRight":0,
               "paddingBottom":0,
               "paddingLeft":0,
               "border":0,
               "indent":0,
               "textField":null,
               "textNaturalWidth":0,
               "sourceIndex":parent == null ? 0 : (parent.children as Array).length,
               "zIndex":int(style["z-index"])
            };
            boxes.push(box);
            if(parent == null)
            {
               root = box;
            }
            else
            {
               parent.children.push(box);
               Sprite(parent.sprite).addChild(sprite);
            }
            if(node.type == CanvasHtmlNode.ELEMENT && !this.isLeaf(node.name))
            {
               var childAncestors:Array = ancestors.concat([node]);
               for(var childIndex:int = node.children.length - 1; childIndex >= 0; childIndex--)
               {
                  frames.push({"node":node.children[childIndex],"parent":box,"ancestors":childAncestors});
               }
            }
         }
         if(root == null)
         {
            this.reject("empty-document",param1.resource);
            return null;
         }
         return {"root":root,"boxes":boxes};
      }

      private function resolveWidths(param1:Array, param2:Object) : Boolean
      {
         param2.available = this.viewportWidth;
         var box:Object = null;
         for each(box in param1)
         {
            var basis:Number = Math.max(1,Number(box.available));
            box.marginTop = this.length(box.style["margin-top"],basis,0);
            box.marginRight = this.length(box.style["margin-right"],basis,0);
            box.marginBottom = this.length(box.style["margin-bottom"],basis,0);
            box.marginLeft = this.length(box.style["margin-left"],basis,0);
            box.paddingTop = this.length(box.style["padding-top"],basis,0);
            box.paddingRight = this.length(box.style["padding-right"],basis,0);
            box.paddingBottom = this.length(box.style["padding-bottom"],basis,0);
            box.paddingLeft = this.length(box.style["padding-left"],basis,0);
            box.border = box.style["border-style"] == "solid" ? this.length(box.style["border-width"],basis,0) : 0;
            var width:Number = Number(box.assignedWidth);
            if(width < 0)
            {
               if(box.style["width"] != "auto")
               {
                  width = CanvasCssValue.resolveLength(String(box.style["width"]),basis,basis);
               }
               else
               {
                  width = this.intrinsicWidth(box,basis - Number(box.marginLeft) - Number(box.marginRight));
               }
            }
            if(!isFinite(width) || width <= 0 || width > 8192)
            {
               return this.reject("invalid-width",CanvasHtmlNode(box.node).resource);
            }
            box.width = width;
            box.innerWidth = Math.max(1,width - Number(box.paddingLeft) - Number(box.paddingRight) - Number(box.border) * 2);
            if(CanvasHtmlNode(box.node).name == "li" && box.parent != null && (CanvasHtmlNode(box.parent.node).name == "ul" || CanvasHtmlNode(box.parent.node).name == "ol"))
            {
               box.indent = 24;
            }
            if(!this.assignChildWidths(box))
            {
               return false;
            }
         }
         return true;
      }

      private function assignChildWidths(param1:Object) : Boolean
      {
         var children:Array = param1.children as Array;
         if(children.length == 0)
         {
            return true;
         }
         var available:Number = Math.max(1,Number(param1.innerWidth) - Number(param1.indent));
         var row:Boolean = param1.style["display"] == "flex" && param1.style["flex-direction"] == "row";
         if(!row)
         {
            var columnChild:Object = null;
            for each(columnChild in children)
            {
               columnChild.available = available;
            }
            return true;
         }
         var gap:Number = this.length(param1.style["gap"],available,0);
         var flowCount:int = 0;
         var counted:Object = null;
         for each(counted in children)
         {
            if(counted.style["position"] != "absolute")
            {
               flowCount++;
            }
         }
         var fixed:Number = gap * Math.max(0,flowCount - 1);
         var autoCount:int = 0;
         var child:Object = null;
         for each(child in children)
         {
            if(child.style["position"] == "absolute")
            {
               child.available = available;
               continue;
            }
            var childMargins:Number = this.length(child.style["margin-left"],available,0) + this.length(child.style["margin-right"],available,0);
            if(child.style["width"] == "auto")
            {
               autoCount++;
               fixed += childMargins;
            }
            else
            {
               var fixedWidth:Number = CanvasCssValue.resolveLength(String(child.style["width"]),available,available);
               child.assignedWidth = fixedWidth;
               fixed += fixedWidth + childMargins;
            }
         }
         var allocation:Number = autoCount == 0 ? 1 : (available - fixed) / autoCount;
         if(autoCount > 0 && allocation <= 0)
         {
            return this.reject("horizontal-overflow",CanvasHtmlNode(param1.node).resource);
         }
         for each(child in children)
         {
            if(child.style["position"] == "absolute")
            {
               continue;
            }
            if(child.style["width"] == "auto")
            {
               child.assignedWidth = Math.max(1,allocation);
            }
            child.available = Number(child.assignedWidth);
         }
         return true;
      }

      private function measureLeaves(param1:Array) : Boolean
      {
         var box:Object = null;
         for each(box in param1)
         {
            var node:CanvasHtmlNode = box.node as CanvasHtmlNode;
            if(node.type == CanvasHtmlNode.TEXT)
            {
               var format:TextFormat = this.createTextFormat(box.style);
               var field:TextField = new TextField();
               field.embedFonts = true;
               field.multiline = true;
               field.wordWrap = true;
               field.selectable = false;
               field.mouseEnabled = false;
               field.defaultTextFormat = format;
               field.width = Math.max(1,Number(box.innerWidth));
               field.text = node.text == null ? "" : node.text;
               field.setTextFormat(format);
               field.height = Math.max(1,field.textHeight + 6);
               Sprite(box.sprite).addChild(field);
               box.textField = field;
               box.textNaturalWidth = Math.min(Number(box.innerWidth),field.textWidth + 6);
               box.contentHeight = field.height;
            }
            else if(node.name == "br")
            {
               box.contentHeight = this.lineHeight(box.style);
            }
            else if(node.name == "hr")
            {
               box.contentHeight = Math.max(2,Number(box.border));
            }
            else if(node.name == "vw-meter")
            {
               box.contentHeight = 18;
            }
            else if(node.name == "svg" || node.name == "img")
            {
               if(!this.measureAsset(box,node))
               {
                  return false;
               }
            }
         }
         return true;
      }

      private function resolveHeights(param1:Array) : Boolean
      {
         for(var index:int = param1.length - 1; index >= 0; index--)
         {
            var box:Object = param1[index];
            var children:Array = box.children as Array;
            var row:Boolean = box.style["display"] == "flex" && box.style["flex-direction"] == "row";
            var columnFlex:Boolean = box.style["display"] == "flex" && box.style["flex-direction"] == "column";
            var gap:Number = box.style["display"] == "flex" ? this.length(box.style["gap"],Number(box.innerWidth),0) : 0;
            this.shrinkInlineBox(box);
            var startX:Number = Number(box.border) + Number(box.paddingLeft) + Number(box.indent);
            var startY:Number = Number(box.border) + Number(box.paddingTop);
            var cursor:Number = row ? startX : startY;
            var lineX:Number = startX;
            var lineY:Number = startY;
            var currentLineHeight:Number = 0;
            var contentHeight:Number = Number(box.contentHeight);
            var child:Object = null;
            for each(child in children)
            {
               if(child.style["position"] == "absolute")
               {
                  continue;
               }
               if(row)
               {
                  Sprite(child.sprite).x = cursor + Number(child.marginLeft);
                  Sprite(child.sprite).y = startY + Number(child.marginTop);
                  cursor += Number(child.marginLeft) + Number(child.width) + Number(child.marginRight) + gap;
                  contentHeight = Math.max(contentHeight,Number(child.marginTop) + Number(child.height) + Number(child.marginBottom));
               }
               else if(!columnFlex && child.style["display"] == "inline")
               {
                  var childWidth:Number = Number(child.marginLeft) + Number(child.width) + Number(child.marginRight);
                  var childHeight:Number = Number(child.marginTop) + Number(child.height) + Number(child.marginBottom);
                  if(CanvasHtmlNode(child.node).name == "br")
                  {
                     lineY += Math.max(currentLineHeight,childHeight);
                     lineX = startX;
                     currentLineHeight = 0;
                     Sprite(child.sprite).x = lineX;
                     Sprite(child.sprite).y = lineY;
                     continue;
                  }
                  if(lineX > startX && lineX + childWidth > startX + Number(box.innerWidth) - Number(box.indent))
                  {
                     lineY += currentLineHeight;
                     lineX = startX;
                     currentLineHeight = 0;
                  }
                  Sprite(child.sprite).x = lineX + Number(child.marginLeft);
                  Sprite(child.sprite).y = lineY + Number(child.marginTop);
                  lineX += childWidth;
                  currentLineHeight = Math.max(currentLineHeight,childHeight);
                  contentHeight = Math.max(contentHeight,lineY - startY + currentLineHeight);
               }
               else
               {
                  if(!columnFlex && currentLineHeight > 0)
                  {
                     cursor = Math.max(cursor,lineY + currentLineHeight);
                     lineY = cursor;
                     lineX = startX;
                     currentLineHeight = 0;
                  }
                  Sprite(child.sprite).x = startX + Number(child.marginLeft);
                  Sprite(child.sprite).y = cursor + Number(child.marginTop);
                  cursor += Number(child.marginTop) + Number(child.height) + Number(child.marginBottom) + gap;
                  contentHeight = cursor - startY - gap;
                  lineY = cursor;
               }
            }
            if(!row && !columnFlex && currentLineHeight > 0)
            {
               contentHeight = Math.max(contentHeight,lineY - startY + currentLineHeight);
            }
            var naturalHeight:Number = Number(box.border) * 2 + Number(box.paddingTop) + Number(box.paddingBottom) + Math.max(0,contentHeight);
            var requestedHeight:Number = box.style["height"] == "auto" ? naturalHeight : CanvasCssValue.resolveLength(String(box.style["height"]),this.viewportHeight,naturalHeight);
            if(!isFinite(requestedHeight) || requestedHeight < 0 || requestedHeight > 8192)
            {
               return this.reject("invalid-height",CanvasHtmlNode(box.node).resource);
            }
            box.height = Math.max(1,requestedHeight);
            var innerHeight:Number = Math.max(1,Number(box.height) - Number(box.border) * 2 - Number(box.paddingTop) - Number(box.paddingBottom));
            for each(child in children)
            {
               if(child.style["position"] == "absolute")
               {
                  if(box.style["position"] == "static")
                  {
                     return this.reject("absolute-containing-block-required",CanvasHtmlNode(child.node).resource);
                  }
                  Sprite(child.sprite).x = startX + Number(child.marginLeft) + this.length(child.style["left"],Number(box.innerWidth),0);
                  Sprite(child.sprite).y = startY + Number(child.marginTop) + this.length(child.style["top"],innerHeight,0);
               }
               else if(child.style["position"] == "relative")
               {
                  Sprite(child.sprite).x += this.length(child.style["left"],Number(box.innerWidth),0);
                  Sprite(child.sprite).y += this.length(child.style["top"],innerHeight,0);
               }
               if(!this.isBoundedCoordinate(Sprite(child.sprite).x) || !this.isBoundedCoordinate(Sprite(child.sprite).y))
               {
                  return this.reject("invalid-position",CanvasHtmlNode(child.node).resource);
               }
            }
            this.applyZOrder(box);
            this.drawBox(box);
         }
         return true;
      }

      private function measureAsset(param1:Object, param2:CanvasHtmlNode) : Boolean
      {
         if(param2.name == "img" && this.resolveImageResource(param2) == null)
         {
            return this.reject("invalid-image",param2.resource,"asset");
         }
         return this.measureSvg(param1,param2);
      }

      private function resolveImageResource(param1:CanvasHtmlNode) : CanvasHtmlResource
      {
         var resolved:String = CanvasHtmlPath.resolve(param1.resource,param1.getAttribute("src"));
         var resource:CanvasHtmlResource = resolved == null ? null : this.resources[resolved] as CanvasHtmlResource;
         return resource != null && resource.kind == "svg" ? resource : null;
      }

      private function measureSvg(param1:Object, param2:CanvasHtmlNode) : Boolean
      {
         this.currentSvgResource = param2.resource;
         var svg:CanvasHtmlNode = this.resolveSvg(param2);
         if(svg == null)
         {
            return this.reject("invalid-svg",param2.resource,"asset");
         }
         var viewbox:Array = this.parseViewbox(svg.getAttribute("viewbox"));
         if(viewbox == null || Number(viewbox[2]) <= 0 || Number(viewbox[3]) <= 0 || Math.abs(Number(viewbox[0]) + Number(viewbox[2])) > CanvasHtmlLimits.MAX_SVG_COORDINATE || Math.abs(Number(viewbox[1]) + Number(viewbox[3])) > CanvasHtmlLimits.MAX_SVG_COORDINATE)
         {
            return this.reject("invalid-svg",param2.resource,"asset");
         }
         var width:Number = Math.max(1,Number(param1.innerWidth));
         var height:Number = width * Number(viewbox[3]) / Number(viewbox[2]);
         if(param1.style["height"] != "auto")
         {
            height = Math.max(1,CanvasCssValue.resolveLength(String(param1.style["height"]),this.viewportHeight,height) - Number(param1.paddingTop) - Number(param1.paddingBottom) - Number(param1.border) * 2);
         }
         if(!this.isBoundedCoordinate(width) || !this.isBoundedCoordinate(height))
         {
            return this.reject("invalid-svg-size",param2.resource,"asset");
         }
         var shape:Shape = new Shape();
         var color:Object = CanvasCssValue.parseColor(String(param1.style["color"]));
         var paths:Array = svg.children;
         var path:CanvasHtmlNode = null;
         if(paths.length == 0)
         {
            return this.reject("invalid-svg",param2.resource,"asset");
         }
         for each(path in paths)
         {
            if(path.type != CanvasHtmlNode.ELEMENT || path.name != "path" || !CanvasSvgPathRenderer.render(path,shape.graphics,viewbox,width / Number(viewbox[2]),height / Number(viewbox[3]),color,this.consumeSvgWork))
            {
               return this.reject("unsupported-svg-path",param2.resource,"asset");
            }
         }
         shape.x = Number(param1.border) + Number(param1.paddingLeft);
         shape.y = Number(param1.border) + Number(param1.paddingTop);
         Sprite(param1.sprite).addChild(shape);
         param1.contentHeight = height;
         this.currentSvgResource = null;
         return true;
      }

      private function resolveSvg(param1:CanvasHtmlNode) : CanvasHtmlNode
      {
         if(param1.name == "svg")
         {
            return param1;
         }
         var resolved:String = CanvasHtmlPath.resolve(param1.resource,param1.getAttribute("src"));
         var resource:CanvasHtmlResource = resolved == null ? null : this.resources[resolved] as CanvasHtmlResource;
         if(resource == null || resource.kind != "svg" || resource.text == null || resource.text.length + 80 > CanvasHtmlLimits.MAX_STRING_CODE_UNITS * 16)
         {
            return null;
         }
         var cacheKey:String = "$" + resolved;
         if(this.svgCache.hasOwnProperty(cacheKey))
         {
            return this.svgCache[cacheKey] as CanvasHtmlNode;
         }
         if(!this.consumeSvgWork(resource.text.length))
         {
            return null;
         }
         var wrapped:String = "<!doctype html><html><head><title>svg</title></head><body>" + resource.text + "</body></html>";
         var parsed:CanvasHtmlParseResult = new CanvasHtmlParser().parse(wrapped,resource.path);
         if(!parsed.success)
         {
            this.svgCache[cacheKey] = null;
            return null;
         }
         var rootChild:CanvasHtmlNode = null;
         var body:CanvasHtmlNode = null;
         for each(rootChild in parsed.document.root.children)
         {
            if(rootChild.name == "body")
            {
               body = rootChild;
               break;
            }
         }
         var result:CanvasHtmlNode = body == null || body.children.length != 1 || CanvasHtmlNode(body.children[0]).name != "svg" ? null : body.children[0] as CanvasHtmlNode;
         this.svgCache[cacheKey] = result;
         return result;
      }

      private function parseViewbox(param1:String) : Array
      {
         if(param1 == null)
         {
            return null;
         }
         var values:Array = param1.split(" ");
         if(values.length != 4)
         {
            return null;
         }
         var result:Array = [];
         var value:String = null;
         for each(value in values)
         {
            var number:Number = Number(value);
            if(!isFinite(number) || Math.abs(number) > CanvasHtmlLimits.MAX_SVG_COORDINATE)
            {
               return null;
            }
            result.push(number);
         }
         return result;
      }

      private function drawBox(param1:Object) : void
      {
         var sprite:Sprite = param1.sprite as Sprite;
         var background:Object = CanvasCssValue.parseColor(String(param1.style["background-color"]));
         var borderColor:Object = CanvasCssValue.parseColor(String(param1.style["border-color"]));
         sprite.graphics.clear();
         if(background != null && Number(background.alpha) > 0)
         {
            sprite.graphics.beginFill(uint(background.color),Number(background.alpha));
            sprite.graphics.drawRect(0,0,Number(param1.width),Number(param1.height));
            sprite.graphics.endFill();
         }
         if(Number(param1.border) > 0 && borderColor != null && Number(borderColor.alpha) > 0)
         {
            sprite.graphics.lineStyle(Number(param1.border),uint(borderColor.color),Number(borderColor.alpha));
            sprite.graphics.drawRect(Number(param1.border) * 0.5,Number(param1.border) * 0.5,Math.max(0,Number(param1.width) - Number(param1.border)),Math.max(0,Number(param1.height) - Number(param1.border)));
         }
         sprite.alpha = Number(param1.style["opacity"]);
         if(param1.style["overflow"] == "hidden")
         {
            sprite.scrollRect = new Rectangle(0,0,Number(param1.width),Number(param1.height));
         }
         var node:CanvasHtmlNode = param1.node as CanvasHtmlNode;
         if(node.name == "hr")
         {
            var rule:Shape = new Shape();
            var ruleColor:Object = CanvasCssValue.parseColor(String(param1.style["color"]));
            rule.graphics.lineStyle(Math.max(1,Number(param1.border)),uint(ruleColor.color),Number(ruleColor.alpha));
            rule.graphics.moveTo(Number(param1.border) + Number(param1.paddingLeft),Number(param1.height) * 0.5);
            rule.graphics.lineTo(Number(param1.width) - Number(param1.border) - Number(param1.paddingRight),Number(param1.height) * 0.5);
            sprite.addChild(rule);
         }
         else if(node.name == "vw-meter")
         {
            var meter:Shape = new Shape();
            var track:Object = background == null || Number(background.alpha) == 0 ? {"color":3158064,"alpha":1} : background;
            var fill:Object = CanvasCssValue.parseColor(String(param1.style["color"]));
            var meterX:Number = Number(param1.border) + Number(param1.paddingLeft);
            var meterY:Number = Number(param1.border) + Number(param1.paddingTop);
            var meterWidth:Number = Math.max(1,Number(param1.innerWidth));
            var meterHeight:Number = Math.max(1,Number(param1.height) - Number(param1.border) * 2 - Number(param1.paddingTop) - Number(param1.paddingBottom));
            var meterValue:Number = Number(node.bindingValue);
            if(meterValue > 1)
            {
               meterValue /= 100;
            }
            meterValue = Math.max(0,Math.min(1,meterValue));
            meter.graphics.beginFill(uint(track.color),Number(track.alpha));
            meter.graphics.drawRect(meterX,meterY,meterWidth,meterHeight);
            meter.graphics.endFill();
            meter.graphics.beginFill(uint(fill.color),Number(fill.alpha));
            meter.graphics.drawRect(meterX,meterY,meterWidth * meterValue,meterHeight);
            meter.graphics.endFill();
            sprite.addChild(meter);
         }
         if(node.name == "li" && param1.parent != null)
         {
            var parentName:String = CanvasHtmlNode(param1.parent.node).name;
            var marker:TextField = new TextField();
            var markerFormat:TextFormat = this.createTextFormat(param1.style);
            marker.embedFonts = true;
            marker.selectable = false;
            marker.mouseEnabled = false;
            marker.width = 22;
            marker.height = this.lineHeight(param1.style) + 4;
            marker.defaultTextFormat = markerFormat;
            marker.text = parentName == "ol" ? String((param1.parent.children as Array).indexOf(param1) + 1) + "." : "-";
            marker.setTextFormat(markerFormat);
            marker.x = Number(param1.border) + Number(param1.paddingLeft);
            marker.y = Number(param1.border) + Number(param1.paddingTop);
            sprite.addChild(marker);
         }
      }

      private function createTextFormat(param1:Object) : TextFormat
      {
         var color:Object = CanvasCssValue.parseColor(String(param1["color"]));
         var size:Object = CanvasCssValue.parseLength(String(param1["font-size"]),false,false,false);
         var format:TextFormat = new TextFormat(String(param1["font-family"]),Number(size.value),uint(color.color),param1["font-weight"] == "bold");
         format.align = String(param1["text-align"]);
         if(param1["line-height"] != "normal")
         {
            var line:Object = CanvasCssValue.parseLength(String(param1["line-height"]),false,false,false);
            format.leading = Math.max(1 - Number(size.value),Number(line.value) - Number(size.value));
         }
         return format;
      }

      private function lineHeight(param1:Object) : Number
      {
         var font:Object = CanvasCssValue.parseLength(String(param1["font-size"]),false,false,false);
         if(param1["line-height"] == "normal")
         {
            return Number(font.value) * 1.2;
         }
         var line:Object = CanvasCssValue.parseLength(String(param1["line-height"]),false,false,false);
         return Number(line.value);
      }

      private function intrinsicWidth(param1:Object, param2:Number) : Number
      {
         var node:CanvasHtmlNode = param1.node as CanvasHtmlNode;
         if(node.name == "img" || node.name == "svg")
         {
            return Math.min(Math.max(1,param2),64);
         }
         if(node.name == "vw-meter")
         {
            return Math.min(Math.max(1,param2),220);
         }
         return Math.max(1,param2);
      }

      private function shrinkInlineBox(param1:Object) : void
      {
         if(param1.parent == null || param1.style["display"] != "inline" || param1.style["width"] != "auto" || param1.style["text-align"] != "left")
         {
            return;
         }
         var node:CanvasHtmlNode = param1.node as CanvasHtmlNode;
         if(node.name == "img" || node.name == "svg" || node.name == "vw-meter")
         {
            return;
         }
         var desired:Number = Number(param1.textNaturalWidth);
         if(desired <= 0)
         {
            var child:Object = null;
            for each(child in param1.children)
            {
               desired += Number(child.marginLeft) + Number(child.width) + Number(child.marginRight);
            }
            if(desired <= 0)
            {
               desired = 1;
            }
         }
         desired += Number(param1.paddingLeft) + Number(param1.paddingRight) + Number(param1.border) * 2;
         param1.width = Math.max(1,Math.min(Number(param1.width),desired));
         param1.innerWidth = Math.max(1,Number(param1.width) - Number(param1.paddingLeft) - Number(param1.paddingRight) - Number(param1.border) * 2);
         var field:TextField = param1.textField as TextField;
         if(field != null)
         {
            field.width = Number(param1.innerWidth);
            field.height = Math.max(1,field.textHeight + 6);
            param1.contentHeight = field.height;
         }
      }

      private function length(param1:Object, param2:Number, param3:Number) : Number
      {
         return CanvasCssValue.resolveLength(String(param1),param2,param3);
      }

      private function isLeaf(param1:String) : Boolean
      {
         return param1 == "br" || param1 == "hr" || param1 == "img" || param1 == "svg" || param1 == "vw-meter";
      }

      private function applyZOrder(param1:Object) : void
      {
         var children:Array = (param1.children as Array).concat();
         children.sortOn(["zIndex","sourceIndex"],[Array.NUMERIC,Array.NUMERIC]);
         for(var index:int = 0; index < children.length; index++)
         {
            var sprite:Sprite = children[index].sprite as Sprite;
            if(sprite != null && sprite.parent === param1.sprite)
            {
               Sprite(param1.sprite).setChildIndex(sprite,index);
            }
         }
      }

      private function isBoundedCoordinate(param1:Number) : Boolean
      {
         return isFinite(param1) && Math.abs(param1) <= CanvasHtmlLimits.MAX_GRAPHICS_COORDINATE;
      }

      private function consumeSvgWork(param1:int) : Boolean
      {
         if(param1 < 0 || this.svgWork > CanvasHtmlLimits.MAX_SVG_WORK - param1)
         {
            return this.reject("limit-exceeded",this.currentSvgResource,"render","svg-work");
         }
         this.svgWork += param1;
         return true;
      }

      private function disposeDisplay(param1:Sprite) : void
      {
         if(param1 == null)
         {
            return;
         }
         while(param1.numChildren > 0)
         {
            param1.removeChildAt(param1.numChildren - 1);
         }
         param1.graphics.clear();
      }

      private function reject(param1:String, param2:String, param3:String = "render", param4:String = null) : Boolean
      {
         if(this.failure == null)
         {
            this.failure = new CanvasHtmlDiagnostic(param3,param1,param2,-1,param4);
         }
         return false;
      }
   }
}
