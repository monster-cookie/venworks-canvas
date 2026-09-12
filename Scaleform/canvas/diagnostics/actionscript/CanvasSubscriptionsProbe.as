package
{
   import flash.display.MovieClip;
   import flash.utils.getDefinitionByName;

   public final class CanvasSubscriptionsProbe extends MovieClip
   {
      private var marker:CanvasDiagnosticMarker;

      private var passed:int = 0;

      private var failures:Array = [];

      public function CanvasSubscriptionsProbe()
      {
         this.marker = new CanvasDiagnosticMarker(this,"VWCANVAS SUBSCRIPTIONS PROBE",65280);
         this.runCase("SHARED REPLAY FANOUT",this.testSharedReplayFanout);
         this.runCase("REQUEST PREFLIGHT",this.testRequestPreflight);
         this.runCase("SUBSCRIBE ROLLBACK",this.testSubscribeRollback);
         this.runCase("UNSUBSCRIBE RECOVERY",this.testUnsubscribeRecovery);
         this.runCase("REPEAT DISPOSE",this.testRepeatAndDispose);
         this.updateMarker();
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
            "uiChannels":[],
            "eventTopics":[],
            "marker":"SUBSCRIPTIONS-PROBE-TEST-ONLY"
         };
      }

      public function handleUIData(param1:String, param2:Object) : void
      {
      }

      public function handleCanvasEvent(param1:String, param2:String) : void
      {
      }

      public function handleLifecycle(param1:String, param2:Object) : void
      {
         if(param1 == "ready")
         {
            this.updateMarker();
         }
      }

      public function dispose() : void
      {
         if(this.marker != null)
         {
            this.marker.dispose();
            this.marker = null;
         }
      }

      private function testSharedReplayFanout() : void
      {
         var manager:CanvasSubscriptionsFakeManager = new CanvasSubscriptionsFakeManager();
         manager.setReplay("PlayerData",{"sequence":1});
         var context:CanvasSubscriptionsTestContext = new CanvasSubscriptionsTestContext();
         var registry:Object = this.createRegistry(manager,context);
         var first:CanvasSubscriptionsTestBridge = new CanvasSubscriptionsTestBridge();
         var second:CanvasSubscriptionsTestBridge = new CanvasSubscriptionsTestBridge();
         var firstLoader:Object = {};
         var secondLoader:Object = {};
         this.addConsumer(registry,context,"consumer-a",first,firstLoader,1,["PlayerData"],["venworks.canvas.test"]);
         this.assertTrue(first.dataChannels.length == 0,"synchronous replay escaped readiness");
         this.addConsumer(registry,context,"consumer-b",second,secondLoader,2,["PlayerData"],["venworks.canvas.test"]);
         this.assertTrue(manager.countGets("PlayerData") == 1,"shared channel fetched more than once");
         this.assertTrue(manager.countSubscribes("PlayerData") == 1,"shared channel subscribed more than once");
         var sharedCallback:Function = manager.firstSubscribedCallback("PlayerData");
         first.handleLifecycle("ready",{});
         registry["markReady"]("consumer-a");
         second.handleLifecycle("ready",{});
         registry["markReady"]("consumer-b");
         this.assertTrue(first.order.join(",") == "ready,data:PlayerData","first replay preceded readiness");
         this.assertTrue(second.order.join(",") == "ready,data:PlayerData","second replay preceded readiness");
         first.throwData = true;
         manager.emit("PlayerData",{"sequence":2});
         this.assertTrue(first.dataChannels.length == 2,"throwing data consumer did not receive update");
         this.assertTrue(second.dataChannels.length == 2,"throwing data consumer stopped fan-out");
         first.throwData = false;
         first.throwEvent = true;
         registry["publishEvent"]("venworks.canvas.test","event-body");
         this.assertTrue(first.eventTopics.length == 1,"throwing event consumer did not receive event");
         this.assertTrue(second.eventTopics.length == 1,"throwing event consumer stopped fan-out");
         first.onData = function(param1:String, param2:Object):void
         {
            registry["removeConsumer"]("consumer-a");
            context.deactivate("consumer-a");
         };
         manager.emit("PlayerData",{"sequence":3});
         this.assertTrue(second.dataChannels.length == 3,"self-removal stopped remaining fan-out");
         registry["removeConsumer"]("consumer-b");
         context.deactivate("consumer-b");
         this.assertTrue(manager.countUnsubscribes("PlayerData") == 1,"final member did not unsubscribe once");
         this.assertTrue(manager.wasUnsubscribedWith("PlayerData",sharedCallback),"unsubscribe callback identity changed");
         var priorCount:int = second.dataChannels.length;
         sharedCallback({"data":{"sequence":4}});
         this.assertTrue(second.dataChannels.length == priorCount,"stale channel callback remained active");
         registry["dispose"]();
      }

      private function testRequestPreflight() : void
      {
         this.assertRejectedBeforeProvider(["PlayerData","UnsupportedData"],[],"unsupported channel");
         this.assertRejectedBeforeProvider(["PlayerData","PlayerData"],[],"duplicate channel");
         this.assertRejectedBeforeProvider(["playerData"],[],"wrong-case channel");
         this.assertRejectedBeforeProvider(["PlayerData"],["invalid"],"invalid topic after valid channel");
         this.assertRejectedBeforeProvider([
            "LocalEnvironmentData","LocalEnvData_Frequent","PlayerData","PlayerFrequentData","PlayerInventoryData","WeaponData",
            "HudJetpackData","HUDStarbornPowersData","FavoritesData","ControlMapData","EnvironmentEffectsData","PersonalEffectsData",
            "StarmapSystemBodyInfoProvider","HudCompassData","HudCrosshairData","HUDStealthData","HUDVehicleData","HUDOpacityData","PlayerData"
         ],[],"over-limit channel request");
      }

      private function testSubscribeRollback() : void
      {
         var manager:CanvasSubscriptionsFakeManager = new CanvasSubscriptionsFakeManager();
         manager.failSubscribe("WeaponData",1);
         var context:CanvasSubscriptionsTestContext = new CanvasSubscriptionsTestContext();
         var registry:Object = this.createRegistry(manager,context);
         var bridge:CanvasSubscriptionsTestBridge = new CanvasSubscriptionsTestBridge();
         var loader:Object = {};
         context.activate("rollback",loader,1);
         var rejected:Boolean = false;
         try
         {
            registry["addConsumer"]("rollback",bridge,loader,1,["PlayerData","WeaponData"],[]);
         }
         catch(subscriptionError:*)
         {
            rejected = true;
         }
         this.assertTrue(rejected,"failed native subscribe was accepted");
         this.assertTrue(manager.activeCallbackCount("PlayerData") == 0,"earlier channel survived rollback");
         this.assertTrue(manager.activeCallbackCount("WeaponData") == 0,"throwing channel survived cleanup");
         this.assertTrue(manager.wasUnsubscribedWith("PlayerData",manager.firstSubscribedCallback("PlayerData")),"rollback changed first callback identity");
         this.assertTrue(manager.wasUnsubscribedWith("WeaponData",manager.firstSubscribedCallback("WeaponData")),"cleanup changed throwing callback identity");
         registry["addConsumer"]("rollback",bridge,loader,1,["PlayerData"],[]);
         this.assertTrue(manager.countSubscribes("PlayerData") == 2,"rolled-back membership blocked retry");
         registry["removeConsumer"]("rollback");
         context.deactivate("rollback");
         registry["dispose"]();
      }

      private function testUnsubscribeRecovery() : void
      {
         var manager:CanvasSubscriptionsFakeManager = new CanvasSubscriptionsFakeManager();
         var context:CanvasSubscriptionsTestContext = new CanvasSubscriptionsTestContext();
         var registry:Object = this.createRegistry(manager,context);
         var firstLoader:Object = {};
         var first:CanvasSubscriptionsTestBridge = new CanvasSubscriptionsTestBridge();
         this.addConsumer(registry,context,"cleanup-a",first,firstLoader,1,["PlayerData"],[]);
         var retiredCallback:Function = manager.firstSubscribedCallback("PlayerData");
         manager.failUnsubscribe("PlayerData",2);
         registry["removeConsumer"]("cleanup-a");
         context.deactivate("cleanup-a");
         this.assertTrue(manager.activeCallbackCount("PlayerData") == 1,"failed unsubscribe lost native callback model");
         var secondLoader:Object = {};
         var second:CanvasSubscriptionsTestBridge = new CanvasSubscriptionsTestBridge();
         context.activate("cleanup-b",secondLoader,2);
         var rejected:Boolean = false;
         try
         {
            registry["addConsumer"]("cleanup-b",second,secondLoader,2,["PlayerData"],[]);
         }
         catch(cleanupError:*)
         {
            rejected = true;
         }
         this.assertTrue(rejected,"unresolved cleanup allowed replacement subscription");
         this.assertTrue(manager.countGets("PlayerData") == 1,"cleanup failure touched provider acquisition");
         this.assertTrue(manager.countSubscribes("PlayerData") == 1,"cleanup failure overlapped native subscription");
         this.assertTrue(manager.activeCallbackCount("PlayerData") == 1,"cleanup failure changed native callback count");
         registry["addConsumer"]("cleanup-b",second,secondLoader,2,["PlayerData"],[]);
         this.assertTrue(manager.countUnsubscribesWith("PlayerData",retiredCallback) == 3,"cleanup retry did not preserve callback identity");
         this.assertTrue(manager.countSubscribes("PlayerData") == 2,"resolved cleanup did not install replacement");
         this.assertTrue(manager.maximumActiveCallbackCount("PlayerData") == 1,"cleanup recovery overlapped callbacks");
         this.assertTrue(manager.onlyActiveCallback("PlayerData") !== retiredCallback,"cleanup recovery reused retired callback");
         registry["markReady"]("cleanup-b");
         var replacementCount:int = second.dataChannels.length;
         retiredCallback({"data":{"sequence":0}});
         this.assertTrue(second.dataChannels.length == replacementCount,"retired callback reached replacement consumer");
         manager.emit("PlayerData",{"sequence":1});
         this.assertTrue(second.dataChannels.length == 1,"replacement did not receive provider data");
         registry["removeConsumer"]("cleanup-b");
         context.deactivate("cleanup-b");
         registry["dispose"]();
      }

      private function testRepeatAndDispose() : void
      {
         var manager:CanvasSubscriptionsFakeManager = new CanvasSubscriptionsFakeManager();
         var context:CanvasSubscriptionsTestContext = new CanvasSubscriptionsTestContext();
         var registry:Object = this.createRegistry(manager,context);
         var index:int = 0;
         while(index < 8)
         {
            var bridge:CanvasSubscriptionsTestBridge = new CanvasSubscriptionsTestBridge();
            var loader:Object = {};
            this.addConsumer(registry,context,"repeat",bridge,loader,index + 1,["PlayerData"],[]);
            registry["markReady"]("repeat");
            manager.emit("PlayerData",{"sequence":index});
            this.assertTrue(bridge.dataChannels.length == 1,"repeat cycle missed provider update");
            var retiredCallback:Function = manager.onlyActiveCallback("PlayerData");
            registry["removeConsumer"]("repeat");
            context.deactivate("repeat");
            retiredCallback({"data":{"sequence":100 + index}});
            this.assertTrue(bridge.dataChannels.length == 1,"repeat cycle stale callback delivered");
            this.assertTrue(manager.activeCallbackCount("PlayerData") == 0,"repeat cycle retained native callback");
            index++;
         }
         var finalBridge:CanvasSubscriptionsTestBridge = new CanvasSubscriptionsTestBridge();
         var finalLoader:Object = {};
         this.addConsumer(registry,context,"repeat",finalBridge,finalLoader,9,["PlayerData"],[]);
         registry["markReady"]("repeat");
         var finalCallback:Function = manager.onlyActiveCallback("PlayerData");
         manager.failUnsubscribe("PlayerData",1);
         registry["dispose"]();
         this.assertTrue(manager.activeCallbackCount("PlayerData") == 0,"dispose did not retry pending cleanup");
         var unsubscribeCount:int = manager.unsubscribeCalls.length;
         registry["dispose"]();
         this.assertTrue(manager.unsubscribeCalls.length == unsubscribeCount,"second dispose repeated cleanup");
         finalCallback({"data":{"sequence":999}});
         this.assertTrue(finalBridge.dataChannels.length == 0,"disposed callback delivered data");
      }

      private function assertRejectedBeforeProvider(param1:Array, param2:Array, param3:String) : void
      {
         var manager:CanvasSubscriptionsFakeManager = new CanvasSubscriptionsFakeManager();
         var context:CanvasSubscriptionsTestContext = new CanvasSubscriptionsTestContext();
         var registry:Object = this.createRegistry(manager,context);
         var bridge:CanvasSubscriptionsTestBridge = new CanvasSubscriptionsTestBridge();
         var loader:Object = {};
         context.activate("preflight",loader,1);
         var rejected:Boolean = false;
         try
         {
            registry["addConsumer"]("preflight",bridge,loader,1,param1,param2);
         }
         catch(validationError:*)
         {
            rejected = true;
         }
         this.assertTrue(rejected,param3 + " was accepted");
         this.assertTrue(manager.getCalls.length == 0,param3 + " reached provider acquisition");
         this.assertTrue(manager.subscribeCalls.length == 0,param3 + " reached native subscribe");
         this.assertTrue(manager.unsubscribeCalls.length == 0,param3 + " reached native unsubscribe");
         registry["addConsumer"]("preflight",bridge,loader,1,[],[]);
         registry["removeConsumer"]("preflight");
         context.deactivate("preflight");
         registry["dispose"]();
      }

      private function createRegistry(param1:CanvasSubscriptionsFakeManager, param2:CanvasSubscriptionsTestContext) : Object
      {
         var subscriptionsType:Class = getDefinitionByName("CanvasSubscriptions") as Class;
         if(subscriptionsType == null)
         {
            throw new Error("CanvasSubscriptions definition unavailable");
         }
         return new subscriptionsType(param1,param2.isCurrent,param2.report);
      }

      private function addConsumer(param1:Object, param2:CanvasSubscriptionsTestContext, param3:String, param4:CanvasSubscriptionsTestBridge, param5:Object, param6:int, param7:Array, param8:Array) : void
      {
         param2.activate(param3,param5,param6);
         param1["addConsumer"](param3,param4,param5,param6,param7,param8);
      }

      private function runCase(param1:String, param2:Function) : void
      {
         try
         {
            param2();
            this.passed++;
         }
         catch(testError:*)
         {
            this.failures.push(param1 + " | " + this.safeText(testError));
         }
      }

      private function assertTrue(param1:Boolean, param2:String) : void
      {
         if(!param1)
         {
            throw new Error(param2);
         }
      }

      private function updateMarker() : void
      {
         if(this.marker == null)
         {
            return;
         }
         var lines:Array = ["PASS " + this.passed + " / 5 | FAIL " + this.failures.length];
         var index:int = 0;
         while(index < this.failures.length && index < 3)
         {
            lines.push(String(this.failures[index]));
            index++;
         }
         if(this.failures.length == 0)
         {
            lines.push("ALL REGISTRY DIAGNOSTICS PASSED");
         }
         this.marker.update(lines);
      }

      private function safeText(param1:*) : String
      {
         var value:String = "unknown failure";
         try
         {
            value = String(param1);
         }
         catch(textError:*)
         {
         }
         value = value.replace(/[\r\n\t]+/g," ");
         return value.length > 90 ? value.substr(0,87) + "..." : value;
      }
   }

}
