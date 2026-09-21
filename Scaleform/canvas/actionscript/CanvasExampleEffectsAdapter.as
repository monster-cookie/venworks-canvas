package
{
   public final class CanvasExampleEffectsAdapter
   {
      private static const MAX_SEQUENCE:int = 1000000000;
      private static const HALF_SEQUENCE:int = 500000000;
      private static const MAX_EFFECTS:int = 2000;
      private static const PAGE_SIZE:int = 8;

      private var buffs:Array = [];
      private var debuffs:Array = [];
      private var hasSnapshot:Boolean;
      private var page:int;
      private var committedSequence:int = -1;
      private var pendingSequence:int = -1;
      private var pendingBuffCount:int;
      private var pendingDebuffCount:int;
      private var pendingParts:Array = [];
      private var receivedParts:int;
      private var removals:Object = {};
      private var removalCount:int;

      public function reset() : void
      {
         this.buffs = [];
         this.debuffs = [];
         this.hasSnapshot = false;
         this.page = 0;
         this.committedSequence = -1;
         this.clearPending();
         this.removals = {};
         this.removalCount = 0;
      }

      // A true result means the visible data changed and needs one Canvas setData call.
      public function acceptPacket(body:String) : Boolean
      {
         if(body == null || body.length == 0 || body.length > 4096)
         {
            return false;
         }
         var fields:Array = body.split("|");
         if(fields.length < 3)
         {
            return false;
         }
         var sequence:int = this.unsigned(String(fields[1]),1,MAX_SEQUENCE);
         if(sequence < 0)
         {
            return false;
         }
         var kind:String = String(fields[0]);
         if(kind == "R" && fields.length == 3)
         {
            return this.acceptRemoval(sequence,String(fields[2]));
         }
         if(kind == "S" && fields.length == 4)
         {
            var buffCount:int = this.unsigned(String(fields[2]),0,MAX_EFFECTS);
            var debuffCount:int = this.unsigned(String(fields[3]),0,MAX_EFFECTS);
            if(buffCount < 0 || debuffCount < 0 || buffCount + debuffCount > MAX_EFFECTS || !this.isNewer(sequence,this.committedSequence))
            {
               return false;
            }
            if(this.pendingSequence >= 0 && !this.isNewer(sequence,this.pendingSequence))
            {
               return false;
            }
            this.clearPending();
            this.pendingSequence = sequence;
            this.pendingBuffCount = buffCount;
            this.pendingDebuffCount = debuffCount;
            return false;
         }
         if(sequence != this.pendingSequence || !this.isNewer(sequence,this.committedSequence))
         {
            return false;
         }
         if(kind == "P" && fields.length == 4)
         {
            var partIndex:int = this.unsigned(String(fields[2]),0,MAX_EFFECTS - 1);
            if(partIndex < 0 || fields[3] == "" || this.pendingParts[partIndex] !== undefined)
            {
               return false;
            }
            this.pendingParts[partIndex] = String(fields[3]);
            this.receivedParts++;
            return false;
         }
         if(kind == "C" && fields.length == 3)
         {
            var partCount:int = this.unsigned(String(fields[2]),0,MAX_EFFECTS);
            var changed:Boolean = partCount >= 0 && this.commit(partCount);
            this.clearPending();
            return changed;
         }
         return false;
      }

      public function advancePage() : Boolean
      {
         var pages:int = this.pageCount();
         if(!this.hasSnapshot || pages < 2)
         {
            return false;
         }
         this.page = (this.page + 1) % pages;
         return true;
      }

      public function view() : Object
      {
         var visibleBuffs:Array = [];
         var visibleDebuffs:Array = [];
         var start:int = this.page * PAGE_SIZE;
         var end:int = Math.min(start + PAGE_SIZE,this.buffs.length + this.debuffs.length);
         for(var index:int = start; index < end; index++)
         {
            var entry:Object = index < this.buffs.length ? this.buffs[index] : this.debuffs[index - this.buffs.length];
            var row:Object = {"label":entry.label};
            if(index < this.buffs.length)
            {
               visibleBuffs.push(row);
            }
            else
            {
               visibleDebuffs.push(row);
            }
         }
         return {
            "waiting":!this.hasSnapshot,
            "empty":this.hasSnapshot && this.buffs.length + this.debuffs.length == 0,
            "hasbuffs":visibleBuffs.length > 0,
            "hasdebuffs":visibleDebuffs.length > 0,
            "buffcount":this.buffs.length,
            "debuffcount":this.debuffs.length,
            "page":this.page + 1,
            "pagecount":this.pageCount(),
            "showpages":this.hasSnapshot && this.pageCount() > 1,
            "buffrows":visibleBuffs,
            "debuffrows":visibleDebuffs
         };
      }

      private function acceptRemoval(sequence:int, encoded:String) : Boolean
      {
         var entry:Object = this.parseEntry(encoded);
         if(entry == null || this.committedSequence >= 0 && this.isNewer(this.committedSequence,sequence))
         {
            return false;
         }
         var removalKey:String = "@" + entry.key;
         if(this.removals.hasOwnProperty(removalKey) && !this.isNewer(sequence,int(this.removals[removalKey])))
         {
            return false;
         }
         if(!this.removals.hasOwnProperty(removalKey))
         {
            if(this.removalCount >= MAX_EFFECTS)
            {
               return false;
            }
            this.removalCount++;
         }
         this.removals[removalKey] = sequence;
         var priorCount:int = this.buffs.length + this.debuffs.length;
         this.buffs = this.withoutEntry(this.buffs,entry.key);
         this.debuffs = this.withoutEntry(this.debuffs,entry.key);
         if(priorCount == this.buffs.length + this.debuffs.length)
         {
            return false;
         }
         this.clampPage();
         return true;
      }

      private function commit(partCount:int) : Boolean
      {
         if(partCount != this.receivedParts || partCount == 0 && this.pendingBuffCount + this.pendingDebuffCount != 0)
         {
            return false;
         }
         var nextBuffs:Array = [];
         var nextDebuffs:Array = [];
         var keys:Object = {};
         for(var partIndex:int = 0; partIndex < partCount; partIndex++)
         {
            if(this.pendingParts[partIndex] === undefined)
            {
               return false;
            }
            var encoded:String = String(this.pendingParts[partIndex]);
            if(encoded.charAt(encoded.length - 1) != ";")
            {
               return false;
            }
            var items:Array = encoded.split(";");
            for(var itemIndex:int = 0; itemIndex < items.length - 1; itemIndex++)
            {
               var entry:Object = this.parseEntry(String(items[itemIndex]));
               if(entry == null || keys.hasOwnProperty("@" + entry.key))
               {
                  return false;
               }
               keys["@" + entry.key] = true;
               if(entry.category == "B")
               {
                  nextBuffs.push(entry);
               }
               else
               {
                  nextDebuffs.push(entry);
               }
               if(nextBuffs.length > this.pendingBuffCount || nextDebuffs.length > this.pendingDebuffCount)
               {
                  return false;
               }
            }
         }
         if(nextBuffs.length != this.pendingBuffCount || nextDebuffs.length != this.pendingDebuffCount)
         {
            return false;
         }
         this.buffs = this.withoutRemoved(nextBuffs,this.pendingSequence);
         this.debuffs = this.withoutRemoved(nextDebuffs,this.pendingSequence);
         this.committedSequence = this.pendingSequence;
         this.hasSnapshot = true;
         this.page = 0;
         this.pruneRemovals();
         return true;
      }

      private function parseEntry(encoded:String) : Object
      {
         if(encoded == null || encoded.length < 3 || encoded.length > 4096 || encoded.charAt(1) != ":" || encoded.indexOf("|") >= 0 || encoded.indexOf(";") >= 0)
         {
            return null;
         }
         var category:String = encoded.charAt(0);
         if(category != "B" && category != "D")
         {
            return null;
         }
         var label:String = encoded.substring(2);
         if(label.charAt(0) == "#")
         {
            var delimiter:int = label.indexOf(":");
            if(delimiter < 2 || !/^-?[0-9]+$/.test(label.substring(1,delimiter)))
            {
               return null;
            }
            label = label.substring(delimiter + 1);
         }
         return label == "" ? null : {"key":encoded,"category":category,"label":label};
      }

      private function withoutEntry(entries:Array, key:String) : Array
      {
         var remaining:Array = [];
         for each(var entry:Object in entries)
         {
            if(entry.key != key)
            {
               remaining.push(entry);
            }
         }
         return remaining;
      }

      private function withoutRemoved(entries:Array, sequence:int) : Array
      {
         var remaining:Array = [];
         for each(var entry:Object in entries)
         {
            var removalKey:String = "@" + entry.key;
            if(!this.removals.hasOwnProperty(removalKey) || this.isNewer(sequence,int(this.removals[removalKey])))
            {
               remaining.push(entry);
            }
         }
         return remaining;
      }

      private function pruneRemovals() : void
      {
         var retained:Object = {};
         var count:int = 0;
         var key:String = null;
         for(key in this.removals)
         {
            if(!this.isNewer(this.committedSequence,int(this.removals[key])))
            {
               retained[key] = this.removals[key];
               count++;
            }
         }
         this.removals = retained;
         this.removalCount = count;
      }

      private function clearPending() : void
      {
         this.pendingSequence = -1;
         this.pendingBuffCount = 0;
         this.pendingDebuffCount = 0;
         this.pendingParts = [];
         this.receivedParts = 0;
      }

      private function pageCount() : int
      {
         return Math.max(1,Math.ceil((this.buffs.length + this.debuffs.length) / PAGE_SIZE));
      }

      private function clampPage() : void
      {
         if(this.page >= this.pageCount())
         {
            this.page = 0;
         }
      }

      private function unsigned(value:String, minimum:int, maximum:int) : int
      {
         if(value == null || !/^[0-9]+$/.test(value))
         {
            return -1;
         }
         var number:Number = Number(value);
         return isFinite(number) && number >= minimum && number <= maximum ? int(number) : -1;
      }

      private function isNewer(candidate:int, reference:int) : Boolean
      {
         if(reference < 0)
         {
            return true;
         }
         var distance:int = candidate - reference;
         return distance > 0 && distance < HALF_SEQUENCE || distance < 0 && -distance > HALF_SEQUENCE;
      }
   }
}
