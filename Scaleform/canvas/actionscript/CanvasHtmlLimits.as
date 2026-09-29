package
{
   // Local theme content. These figures only stop a runaway document.
   // Scaleform cannot draw a graphics coordinate past 16384, so that bound stays.
   public final class CanvasHtmlLimits
   {
      public static const MAX_SOURCE_BYTES:int = 16777216;

      public static const MAX_AGGREGATE_BYTES:int = 67108864;

      public static const MAX_HTML_TOKENS:int = 1048576;

      public static const MAX_DOM_NODES:int = 1048576;

      public static const MAX_DOM_DEPTH:int = 64;

      public static const MAX_ATTRIBUTES_PER_ELEMENT:int = 256;

      public static const MAX_CLASSES_PER_ELEMENT:int = 64;

      public static const MAX_STRING_CODE_UNITS:int = 16777216;

      public static const MAX_IDENTIFIER_LENGTH:int = 1024;

      public static const MAX_EVENT_TOPIC_CODE_UNITS:int = 1024;

      public static const MAX_RESOURCES:int = 4096;

      public static const MAX_INCLUDE_COUNT:int = 4096;

      public static const MAX_INCLUDE_DEPTH:int = 32;

      public static const MAX_STYLESHEETS:int = 256;

      public static const MAX_CSS_RULES:int = 65536;

      public static const MAX_CSS_SELECTORS_PER_RULE:int = 64;

      public static const MAX_CSS_DECLARATIONS_PER_RULE:int = 256;

      public static const MAX_CSS_SELECTOR_PARTS:int = 32;

      public static const MAX_CSS_SELECTOR_CODE_UNITS:int = 8192;

      public static const MAX_CSS_QUALIFIERS_PER_PART:int = 32;

      public static const MAX_CSS_MATCH_WORK:int = 16777216;

      public static const MAX_CSS_IMPORT_DEPTH:int = 32;

      public static const MAX_CSS_IMPORTS:int = 1024;

      public static const MAX_GENERATED_NODES:int = 1048576;

      public static const MAX_COMPOSITION_WORK:int = 16777216;

      public static const MAX_REPEAT_ITEMS:int = 65536;

      public static const MAX_DATA_NODES:int = 1048576;

      public static const MAX_DATA_DEPTH:int = 64;

      public static const MAX_DATA_PROPERTIES:int = 65536;

      public static const MAX_DATA_ENTRIES:int = 1048576;

      public static const MAX_DATA_STRING_CODE_UNITS:int = 16777216;

      public static const MAX_FORMAT_CODE_UNITS:int = 16384;

      public static const MAX_TEMPLATE_VARIABLES:int = 64;

      public static const MAX_SVG_PATH_TOKENS:int = 1048576;

      public static const MAX_SVG_ELEMENTS:int = 65536;

      public static const MAX_SVG_COORDINATE:Number = 16384;

      public static const MAX_GRAPHICS_COORDINATE:Number = 16384;

      public static const MAX_SVG_STROKE_WIDTH:Number = 16384;

      public static const MAX_SVG_WORK:int = 16777216;

      public static const MIN_Z_INDEX:int = -1000000;

      public static const MAX_Z_INDEX:int = 1000000;
   }
}
