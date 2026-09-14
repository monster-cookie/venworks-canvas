package
{
   public final class CanvasHtmlDocument
   {
      public var resource:String;

      public var root:CanvasHtmlNode;

      public var references:Array;

      public var title:String;

      public var tokenCount:int;

      public var nodeCount:int;

      public var maximumDepth:int;

      public var inlineStyleCount:int;

      public function CanvasHtmlDocument(param1:String)
      {
         this.resource = param1;
         this.references = [];
         this.title = "";
      }

      public function getTextPreview(param1:int) : String
      {
         var node:CanvasHtmlNode = null;
         var index:int = 0;
         var output:String = "";
         var stack:Array = [];
         if(this.root != null)
         {
            stack.push(this.root);
         }
         while(stack.length > 0 && output.length < param1)
         {
            node = stack.pop() as CanvasHtmlNode;
            if(node.type == CanvasHtmlNode.TEXT)
            {
               if(output.length > 0)
               {
                  output += " ";
               }
               output += node.text;
               continue;
            }
            for(index = node.children.length - 1; index >= 0; index--)
            {
               stack.push(node.children[index]);
            }
         }
         if(output.length > param1)
         {
            output = output.substr(0,param1);
         }
         return output;
      }
   }
}
