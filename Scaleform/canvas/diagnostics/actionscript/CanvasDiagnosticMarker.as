package
{
   import flash.display.MovieClip;
   import flash.text.TextField;
   import flash.text.TextFormat;

   public final class CanvasDiagnosticMarker
   {
      private var owner:MovieClip;

      private var field:TextField;

      private var label:String;

      private var color:uint;

      public function CanvasDiagnosticMarker(param1:MovieClip, param2:String, param3:uint)
      {
         this.owner = param1;
         this.label = param2;
         this.color = param3;
         var format:TextFormat = new TextFormat("$MAIN_Font_Bold",18,param3,true);
         this.field = new TextField();
         this.field.name = "CanvasDiagnosticMarker";
         this.field.x = 500;
         this.field.y = 610;
         this.field.width = 620;
         this.field.height = 150;
         this.field.background = true;
         this.field.backgroundColor = 2097152;
         this.field.border = true;
         this.field.borderColor = param3;
         this.field.embedFonts = true;
         this.field.defaultTextFormat = format;
         this.field.multiline = true;
         this.field.wordWrap = false;
         this.field.selectable = false;
         this.field.mouseEnabled = false;
         this.owner.addChild(this.field);
         this.update([]);
      }

      public function update(param1:Array) : void
      {
         if(this.field == null)
         {
            return;
         }
         var lines:Array = [this.label + " | TEST ONLY"];
         var index:int = 0;
         while(index < param1.length)
         {
            lines.push(String(param1[index]));
            index++;
         }
         this.field.text = lines.join("\n");
         this.field.setTextFormat(new TextFormat("$MAIN_Font_Bold",18,this.color,true));
      }

      public function dispose() : void
      {
         if(this.field != null && this.field.parent === this.owner)
         {
            this.owner.removeChild(this.field);
         }
         this.field = null;
         this.owner = null;
      }
   }
}
