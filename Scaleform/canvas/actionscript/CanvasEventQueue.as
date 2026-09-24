package
{
   internal final class CanvasEventQueue
   {
      private static const MAX_EVENTS:int = 64;

      private static const MAX_CHARACTERS:int = 65536;

      private var events:Array = [];

      private var characterCount:int = 0;

      public function enqueue(topic:String, body:String, policy:String = "fifo", coalesceKey:String = null) : Boolean
      {
         var eventCharacters:int = topic.length + body.length;
         if(eventCharacters > MAX_CHARACTERS)
         {
            return false;
         }
         if(policy == "latest")
         {
            if(coalesceKey == null || coalesceKey == "")
            {
               coalesceKey = topic;
            }
            var retained:Array = [];
            var retainedCharacters:int = 0;
            for each(var candidate:Object in this.events)
            {
               if(String(candidate.coalesceKey) != coalesceKey)
               {
                  retained.push(candidate);
                  retainedCharacters += int(candidate.characters);
               }
            }
            this.events = retained;
            this.characterCount = retainedCharacters;
         }
         else if(policy != "fifo")
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
         this.events.push({"topic":topic,"body":body,"characters":eventCharacters,"coalesceKey":coalesceKey == null ? "" : coalesceKey});
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

      public function copyForTopic(topic:String) : Array
      {
         var result:Array = [];
         for each(var event:Object in this.events)
         {
            if(String(event.topic) == topic)
            {
               result.push({"topic":String(event.topic),"body":String(event.body),"characters":int(event.characters),"coalesceKey":String(event.coalesceKey)});
            }
         }
         return result;
      }

      public function clear() : void
      {
         this.events = [];
         this.characterCount = 0;
      }
   }
}
