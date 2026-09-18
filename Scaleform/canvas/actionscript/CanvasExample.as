package
{
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.events.TimerEvent;
   import flash.text.TextField;
   import flash.text.TextFormat;
   import flash.utils.Timer;

   public final class CanvasExample extends MovieClip
   {
      private static const TEXT_COLOR:uint = 14941695;
      private static const BUFF_COLOR:uint = 9230318;
      private static const DEBUFF_COLOR:uint = 15232341;
      private static const ACCENT_COLOR:uint = 3845628;
      private static const PANEL_X:Number = 32;
      private static const PANEL_Y:Number = 28;
      private static const PANEL_WIDTH:Number = 500;
      private static const PAGE_SIZE:int = 8;
      private static const ROW_HEIGHT:Number = 42;

      private var panel:Shape;
      private var clockFormat:TextFormat;
      private var buffFormat:TextFormat;
      private var debuffFormat:TextFormat;
      private var universalTimeField:TextField;
      private var localTimeField:TextField;
      private var summaryField:TextField;
      private var pageField:TextField;
      private var effectFields:Array = [];
      private var pageTimer:Timer;
      private var inSpaceship:Boolean = false;
      private var localPlanetTime:Number = NaN;
      private var galacticStandardTime:Number = NaN;
      private var activeBuffs:Array = [];
      private var activeDebuffs:Array = [];
      private var hasSnapshot:Boolean = false;
      private var currentPage:int = 0;
      private var pendingSequence:int = -1;
      private var pendingBuffCount:int = 0;
      private var pendingDebuffCount:int = 0;
      private var pendingParts:Array = [];
      private var receivedPacketCount:int = 0;
      private var receivedPartCount:int = 0;
      private var packetStatus:String = "";

      public function CanvasExample()
      {
         this.clockFormat = new TextFormat("$MAIN_Font_Bold",18,TEXT_COLOR,true);
         this.buffFormat = new TextFormat("$MAIN_Font_Bold",16,BUFF_COLOR,true);
         this.debuffFormat = new TextFormat("$MAIN_Font_Bold",16,DEBUFF_COLOR,true);
         this.createPanel();
         this.pageTimer = new Timer(6000);
         this.pageTimer.addEventListener(TimerEvent.TIMER,this.advancePage);
         this.pageTimer.start();
         this.renderClock();
         this.renderEffects();
      }

      public function getCanvasRegistration() : Object
      {
         return {
            "protocol":"VWCANVAS_CONSUMER/2",
            "consumerId":"a8098c1a-f86e-4b1e-9d7c-5a102bf38460",
            "assetNamespace":"venworks.canvas.example",
            "version":1,
            "minimumContractVersion":2,
            "maximumContractVersion":2,
            "uiChannels":["LocalEnvironmentData","LocalEnvData_Frequent"],
            "eventTopics":["venworks.canvas.example.effects.snapshot"],
            "marker":"EXAMPLE"
         };
      }

      public function handleUIData(channel:String, data:Object) : void
      {
         if(channel == "LocalEnvironmentData")
         {
            this.inSpaceship = this.booleanValue(data,"bInSpaceship",false);
         }
         else if(channel == "LocalEnvData_Frequent")
         {
            this.localPlanetTime = this.numberValue(data,"fLocalPlanetTime",0,1);
            this.galacticStandardTime = this.numberValue(data,"fGalacticStandardTime",0,24);
         }
         this.renderClock();
      }

      public function handleCanvasEvent(topic:String, body:String) : void
      {
         if(topic == "venworks.canvas.example.effects.snapshot")
         {
            this.acceptEffectPacket(body);
         }
      }

      public function handleLifecycle(state:String, detail:Object) : void
      {
         if(state == "ready")
         {
            this.renderClock();
            this.renderEffects();
         }
      }

      public function dispose() : void
      {
         if(this.pageTimer != null)
         {
            this.pageTimer.stop();
            this.pageTimer.removeEventListener(TimerEvent.TIMER,this.advancePage);
            this.pageTimer = null;
         }
         while(numChildren > 0)
         {
            removeChildAt(numChildren - 1);
         }
         this.effectFields = [];
         this.pendingParts = [];
         this.activeBuffs = [];
         this.activeDebuffs = [];
         this.panel = null;
      }

      private function createPanel() : void
      {
         this.panel = new Shape();
         addChild(this.panel);
         this.universalTimeField = this.createField(PANEL_Y + 9,26,this.clockFormat);
         this.localTimeField = this.createField(PANEL_Y + 38,26,this.clockFormat);
         this.summaryField = this.createField(PANEL_Y + 76,26,this.clockFormat);
         this.pageField = this.createField(PANEL_Y + 104,24,this.clockFormat);
         for(var index:int = 0; index < PAGE_SIZE; index++)
         {
            var field:TextField = this.createField(PANEL_Y + 136 + index * ROW_HEIGHT,ROW_HEIGHT - 2,this.buffFormat);
            field.multiline = true;
            field.wordWrap = true;
            this.effectFields.push(field);
         }
      }

      private function createField(y:Number, height:Number, format:TextFormat) : TextField
      {
         var field:TextField = new TextField();
         field.x = PANEL_X + 14;
         field.y = y;
         field.width = PANEL_WIDTH - 28;
         field.height = height;
         field.embedFonts = true;
         field.defaultTextFormat = format;
         field.selectable = false;
         field.mouseEnabled = false;
         addChild(field);
         return field;
      }

      private function acceptEffectPacket(body:String) : void
      {
         this.receivedPacketCount++;
         if(body == null)
         {
            this.packetStatus = "RX " + this.receivedPacketCount + " REJECTED SIZE";
            this.renderEffects();
            return;
         }
         var fields:Array = body.split("|");
         if(fields.length < 3)
         {
            this.packetStatus = "RX " + this.receivedPacketCount + " REJECTED FORMAT";
            this.renderEffects();
            return;
         }
         var sequence:int = this.parseUnsigned(fields[1],1,1000000000);
         if(sequence < 0)
         {
            this.packetStatus = "RX " + this.receivedPacketCount + " REJECTED SEQUENCE";
            this.renderEffects();
            return;
         }
         var kind:String = String(fields[0]).toUpperCase();
         if(kind == "S" && fields.length == 4)
         {
            var buffCount:int = this.parseUnsigned(fields[2],0,2000);
            var debuffCount:int = this.parseUnsigned(fields[3],0,2000);
            if(buffCount < 0 || debuffCount < 0 || buffCount + debuffCount > 2000)
            {
               this.packetStatus = "RX " + this.receivedPacketCount + " REJECTED COUNTS";
               this.renderEffects();
               return;
            }
            this.pendingSequence = sequence;
            this.pendingBuffCount = buffCount;
            this.pendingDebuffCount = debuffCount;
            this.pendingParts = [];
            this.receivedPartCount = 0;
            this.packetStatus = "RX " + this.receivedPacketCount + " SEQ " + sequence + " START";
         }
         else if(kind == "P" && fields.length == 4 && sequence == this.pendingSequence)
         {
            var partIndex:int = this.parseUnsigned(fields[2],0,2000);
            if(partIndex >= 0 && this.pendingParts[partIndex] === undefined)
            {
               this.pendingParts[partIndex] = fields[3];
               this.receivedPartCount++;
               this.packetStatus = "RX " + this.receivedPacketCount + " SEQ " + sequence + " PARTS " + this.receivedPartCount;
            }
            else if(partIndex >= 0)
            {
               this.packetStatus = "RX " + this.receivedPacketCount + " SEQ " + sequence + " DUPLICATE PART " + partIndex;
            }
            else
            {
               this.packetStatus = "RX " + this.receivedPacketCount + " SEQ " + sequence + " REJECTED PART INDEX";
            }
         }
         else if(kind == "C" && fields.length == 3 && sequence == this.pendingSequence)
         {
            var partCount:int = this.parseUnsigned(fields[2],0,2000);
            if(partCount >= 0)
            {
               this.commitEffectSnapshot(partCount);
            }
            else
            {
               this.packetStatus = "RX " + this.receivedPacketCount + " SEQ " + sequence + " REJECTED COMMIT";
            }
            this.pendingSequence = -1;
            this.pendingParts = [];
         }
         else
         {
            this.packetStatus = "RX " + this.receivedPacketCount + " SEQ " + sequence + (kind == "P" ? " PART WITHOUT START" : kind == "C" ? " COMMIT WITHOUT START" : " REJECTED " + kind + "/" + fields.length);
         }
         this.renderEffects();
      }

      private function commitEffectSnapshot(partCount:int) : void
      {
         var buffs:Array = [];
         var debuffs:Array = [];
         for(var partIndex:int = 0; partIndex < partCount; partIndex++)
         {
            if(this.pendingParts[partIndex] === undefined)
            {
               this.packetStatus = "RX " + this.receivedPacketCount + " SEQ " + this.pendingSequence + " MISSING PART " + partIndex;
               return;
            }
            var encoded:Array = String(this.pendingParts[partIndex]).split(";");
            for(var itemIndex:int = 0; itemIndex < encoded.length; itemIndex++)
            {
               var item:String = String(encoded[itemIndex]);
               if(item == "" && itemIndex == encoded.length - 1)
               {
                  continue;
               }
               if(item.length < 3 || item.charAt(1) != ":")
               {
                  this.packetStatus = "RX " + this.receivedPacketCount + " SEQ " + this.pendingSequence + " REJECTED ITEM";
                  return;
               }
               var label:String = item.substring(2);
               if(label.charAt(0) == "#")
               {
                  var identityEnd:int = label.indexOf(":");
                  if(identityEnd < 2 || !/^-?[0-9]+$/.test(label.substring(1,identityEnd)))
                  {
                     this.packetStatus = "RX " + this.receivedPacketCount + " SEQ " + this.pendingSequence + " REJECTED ITEM ID";
                     return;
                  }
                  label = label.substring(identityEnd + 1);
               }
               if(label == "")
               {
                  this.packetStatus = "RX " + this.receivedPacketCount + " SEQ " + this.pendingSequence + " REJECTED ITEM LABEL";
                  return;
               }
               if(item.charAt(0).toUpperCase() == "B")
               {
                  buffs.push(label);
               }
               else if(item.charAt(0).toUpperCase() == "D")
               {
                  debuffs.push(label);
               }
               else
               {
                  this.packetStatus = "RX " + this.receivedPacketCount + " SEQ " + this.pendingSequence + " REJECTED TYPE";
                  return;
               }
            }
         }
         if(buffs.length != this.pendingBuffCount || debuffs.length != this.pendingDebuffCount)
         {
            this.packetStatus = "RX " + this.receivedPacketCount + " SEQ " + this.pendingSequence + " COUNT MISMATCH";
            return;
         }
         this.activeBuffs = buffs;
         this.activeDebuffs = debuffs;
         this.hasSnapshot = true;
         this.currentPage = 0;
         this.packetStatus = "";
      }

      private function advancePage(event:TimerEvent) : void
      {
         var pageCount:int = Math.max(1,Math.ceil((this.activeBuffs.length + this.activeDebuffs.length) / PAGE_SIZE));
         if(pageCount > 1)
         {
            this.currentPage = (this.currentPage + 1) % pageCount;
            this.renderEffects();
         }
      }

      private function renderClock() : void
      {
         this.setText(this.universalTimeField,"UNIVERSAL TIME   " + this.formatClock(this.galacticStandardTime) + " UT",this.clockFormat);
         this.setText(this.localTimeField,"LOCAL TIME       " + (this.inSpaceship ? "--:--" : this.formatClock(this.localPlanetTime * 24)),this.clockFormat);
      }

      private function renderEffects() : void
      {
         var total:int = this.activeBuffs.length + this.activeDebuffs.length;
         var pageCount:int = Math.max(1,Math.ceil(total / PAGE_SIZE));
         var visibleRows:int = this.hasSnapshot ? Math.min(PAGE_SIZE,Math.max(total,1)) : 1;
         this.panel.graphics.clear();
         this.panel.graphics.beginFill(1315860,0.82);
         this.panel.graphics.lineStyle(1,ACCENT_COLOR,0.9);
         this.panel.graphics.drawRect(PANEL_X,PANEL_Y,PANEL_WIDTH,138 + visibleRows * ROW_HEIGHT);
         this.panel.graphics.endFill();
         if(!this.hasSnapshot)
         {
            this.setText(this.summaryField,"ACTIVE EFFECTS | RX " + this.receivedPacketCount,this.clockFormat);
            this.setText(this.pageField,this.packetStatus == "" ? "WAITING FOR DATA-LAYER SNAPSHOT" : this.packetStatus,this.clockFormat);
         }
         else
         {
            this.setText(this.summaryField,"BUFFS " + this.activeBuffs.length + "   DEBUFFS " + this.activeDebuffs.length + " | RX " + this.receivedPacketCount,this.clockFormat);
            this.setText(this.pageField,this.packetStatus != "" ? this.packetStatus : total == 0 ? "NO ACTIVE EFFECTS" : "PAGE " + (this.currentPage + 1) + " / " + pageCount,this.clockFormat);
         }
         for(var index:int = 0; index < PAGE_SIZE; index++)
         {
            var field:TextField = this.effectFields[index];
            var effectIndex:int = this.currentPage * PAGE_SIZE + index;
            var text:String = "";
            var format:TextFormat = this.buffFormat;
            if(this.hasSnapshot && effectIndex < this.activeBuffs.length)
            {
               text = "+ " + this.activeBuffs[effectIndex];
            }
            else if(this.hasSnapshot && effectIndex < total)
            {
               text = "- " + this.activeDebuffs[effectIndex - this.activeBuffs.length];
               format = this.debuffFormat;
            }
            field.visible = text != "";
            this.setText(field,text,format);
         }
      }

      private function setText(field:TextField, value:String, format:TextFormat) : void
      {
         if(field.text != value)
         {
            field.text = value;
            field.setTextFormat(format);
         }
      }

      private function parseUnsigned(value:String, minimum:int, maximum:int) : int
      {
         if(value == null || !/^[0-9]+$/.test(value))
         {
            return -1;
         }
         var number:Number = Number(value);
         return isFinite(number) && number >= minimum && number <= maximum ? int(number) : -1;
      }

      private function formatClock(hours:Number) : String
      {
         if(!isFinite(hours))
         {
            return "--:--";
         }
         var normalized:Number = hours % 24;
         if(normalized < 0)
         {
            normalized += 24;
         }
         var minutes:int = Math.floor(normalized * 60) % 1440;
         return this.pad(Math.floor(minutes / 60)) + ":" + this.pad(minutes % 60);
      }

      private function pad(value:int) : String
      {
         return value < 10 ? "0" + value : String(value);
      }

      private function numberValue(data:Object, field:String, minimum:Number, maximum:Number) : Number
      {
         try
         {
            if(data != null && field in data)
            {
               var value:Number = Number(data[field]);
               if(isFinite(value) && value >= minimum && value <= maximum)
               {
                  return value;
               }
            }
         }
         catch(valueError:*)
         {
         }
         return NaN;
      }

      private function booleanValue(data:Object, field:String, fallback:Boolean) : Boolean
      {
         try
         {
            if(data != null && field in data)
            {
               return data[field] === true;
            }
         }
         catch(valueError:*)
         {
         }
         return fallback;
      }
   }
}
