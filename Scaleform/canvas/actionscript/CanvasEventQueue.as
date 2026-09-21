package
{
   internal final class CanvasEventQueue
   {
      private static const MAX_EVENTS:int = 64;

      private static const MAX_CHARACTERS:int = 65536;

      private var events:Array = [];

      private var characterCount:int = 0;

      public function enqueue(topic:String, body:String) : Boolean
      {
         var eventCharacters:int = topic.length + body.length;
         if(eventCharacters > MAX_CHARACTERS)
         {
            return false;
         }
         var evicted:Boolean = false;
         while(this.events.length > 0 && (this.events.length >= MAX_EVENTS || this.characterCount + eventCharacters > MAX_CHARACTERS))
         {
            var retired:Object = this.events.shift();
            this.characterCount -= int(retired.characters);
            evicted = true;
         }
         this.events.push({"topic":topic,"body":body,"characters":eventCharacters});
         this.characterCount += eventCharacters;
         return evicted;
      }

      public function drain() : Array
      {
         var result:Array = this.events;
         this.events = [];
         this.characterCount = 0;
         return result;
      }

      public function clear() : void
      {
         this.events = [];
         this.characterCount = 0;
      }
   }
}
