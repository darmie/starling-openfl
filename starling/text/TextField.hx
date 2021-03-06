// =================================================================================================
//
//	Starling Framework
//	Copyright 2011 Gamua OG. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.text;
import openfl.display.BitmapData;
import openfl.display.StageQuality;
import openfl.display3D.Context3DTextureFormat;
import openfl.errors.ArgumentError;
import openfl.errors.Error;
import openfl.filters.BitmapFilter;
import openfl.filters.BlurFilter;
import openfl.filters.DropShadowFilter;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.Lib;
import openfl.text.AntiAliasType;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import starling.utils.MathUtil;
import starling.utils.Max;

import starling.core.RenderSupport;
import starling.core.Starling;
import starling.display.DisplayObject;
import starling.display.DisplayObjectContainer;
import starling.display.Image;
import starling.display.Quad;
import starling.display.QuadBatch;
import starling.display.Sprite;
import starling.events.Event;
import starling.textures.Texture;
import starling.utils.HAlign;
import starling.utils.RectangleUtil;
import starling.utils.VAlign;
import starling.utils.Deg2Rad;

/** A TextField displays text, either using standard true type fonts or custom bitmap fonts.
 *  
 *  <p>You can set all properties you are used to, like the font name and size, a color, the 
 *  horizontal and vertical alignment, etc. The border property is helpful during development, 
 *  because it lets you see the bounds of the textfield.</p>
 *  
 *  <p>There are two types of fonts that can be displayed:</p>
 *  
 *  <ul>
 *    <li>Standard TrueType fonts. This renders the text just like a conventional Flash
 *        TextField. It is recommended to embed the font, since you cannot be sure which fonts
 *        are available on the client system, and since this enhances rendering quality. 
 *        Simply pass the font name to the corresponding property.</li>
 *    <li>Bitmap fonts. If you need speed or fancy font effects, use a bitmap font instead. 
 *        That is a font that has its glyphs rendered to a texture atlas. To use it, first 
 *        register the font with the method <code>registerBitmapFont</code>, and then pass 
 *        the font name to the corresponding property of the text field.</li>
 *  </ul> 
 *    
 *  For bitmap fonts, we recommend one of the following tools:
 * 
 *  <ul>
 *    <li>Windows: <a href="http://www.angelcode.com/products/bmfont">Bitmap Font Generator</a>
 *       from Angel Code (free). Export the font data as an XML file and the texture as a png 
 *       with white characters on a transparent background (32 bit).</li>
 *    <li>Mac OS: <a href="http://glyphdesigner.71squared.com">Glyph Designer</a> from 
 *        71squared or <a href="http://http://www.bmglyph.com">bmGlyph</a> (both commercial). 
 *        They support Starling natively.</li>
 *  </ul>
 * 
 *  <strong>Batching of TextFields</strong>
 *  
 *  <p>Normally, TextFields will require exactly one draw call. For TrueType fonts, you cannot
 *  avoid that; bitmap fonts, however, may be batched if you enable the "batchable" property.
 *  This makes sense if you have several TextFields with short texts that are rendered one
 *  after the other (e.g. subsequent children of the same sprite), or if your bitmap font
 *  texture is in your main texture atlas.</p>
 *  
 *  <p>The recommendation is to activate "batchable" if it reduces your draw calls (use the
 *  StatsDisplay to check this) AND if the TextFields contain no more than about 10-15
 *  characters (per TextField). For longer texts, the batching would take up more CPU time
 *  than what is saved by avoiding the draw calls.</p>
 */
class TextField extends DisplayObjectContainer
{
    // the name container with the registered bitmap fonts
    inline private static var BITMAP_FONT_DATA_NAME:String = "starling.display.TextField.BitmapFonts";
    
    // the texture format that is used for TTF rendering
    private static var sDefaultTextureFormat:String = "bgra";
    //    "BGRA_PACKED" in Context3DTextureFormat ? "bgraPacked4444" : "bgra";

    private var mFontSize:Float;
    private var mColor:UInt;
    private var mText:String;
    private var mFontName:String;
    private var mHAlign:String;
    private var mVAlign:String;
    private var mBold:Bool;
    private var mItalic:Bool;
    private var mUnderline:Bool;
    private var mAutoScale:Bool;
    private var mAutoSize:String;
    private var mKerning:Bool;
    private var mNativeFilters:Array<BitmapFilter>;
    private var mRequiresRedraw:Bool;
    private var mIsRenderedText:Bool;
    private var mTextBounds:Rectangle;
    private var mBatchable:Bool;
    
    private var mHitArea:Rectangle;
    private var mBorder:DisplayObjectContainer;
    
    private var mImage:Image;
    private var mQuadBatch:QuadBatch;
    
    /** Helper objects. */
    private static var sHelperMatrix:Matrix = new Matrix();
    private static var sNativeTextField:openfl.text.TextField = new openfl.text.TextField();
    
    /** Create a new text field with the given properties. */
    public function new(width:Int, height:Int, text:String, fontName:String="Verdana",
                              fontSize:Float=12, color:UInt=0x0, bold:Bool=false)
    {
        super();
        mText = text != null ? text : "";
        mFontSize = fontSize;
        mColor = color;
        mHAlign = HAlign.CENTER;
        mVAlign = VAlign.CENTER;
        mBorder = null;
        mKerning = true;
        mBold = bold;
        mAutoSize = TextFieldAutoSize.NONE;
        mHitArea = new Rectangle(0, 0, width, height);
        this.fontName = fontName;
        
        addEventListener(Event.FLATTEN, onFlatten);
    }
    
    /** Disposes the underlying texture data. */
    public override function dispose():Void
    {
        removeEventListener(Event.FLATTEN, onFlatten);
        if (mImage != null) mImage.texture.dispose();
        if (mQuadBatch != null) mQuadBatch.dispose();
        super.dispose();
    }
    
    private function onFlatten(e:Event):Void
    {
        if (mRequiresRedraw) redraw();
    }
    
    /** @inheritDoc */
    public override function render(support:RenderSupport, parentAlpha:Float):Void
    {
        if (mRequiresRedraw) redraw();
        super.render(support, parentAlpha);
    }
    
    /** Forces the text field to be constructed right away. Normally, 
     *  it will only do so lazily, i.e. before being rendered. */
    public function redraw():Void
    {
        if (mRequiresRedraw)
        {
            if (mIsRenderedText) createRenderedContents();
            else                 createComposedContents();
            
            updateBorder();
            mRequiresRedraw = false;
        }
    }
    
    // TrueType font rendering
    
    private function createRenderedContents():Void
    {
        if (mQuadBatch != null)
        {
            mQuadBatch.removeFromParent(true); 
            mQuadBatch = null; 
        }
        
        if (mTextBounds == null) 
            mTextBounds = new Rectangle();
        
        var scale:Float  = Starling.current.contentScaleFactor;
        var bitmapData:BitmapData = renderText(scale, mTextBounds);
        var format:String = sDefaultTextureFormat;
        
        mHitArea.width  = bitmapData.width  / scale;
        mHitArea.height = bitmapData.height / scale;
        
        var texture:Texture = Texture.fromBitmapData(bitmapData, false, false, scale, format);
        texture.root.onRestore = function():Void
        {
            if (mTextBounds == null)
                mTextBounds = new Rectangle();
            
            texture.root.uploadBitmapData(renderText(scale, mTextBounds));
        };
        
        bitmapData.dispose();
        
        if (mImage == null) 
        {
            mImage = new Image(texture);
            mImage.touchable = false;
            addChild(mImage);
        }
        else 
        { 
            mImage.texture.dispose();
            mImage.texture = texture; 
            mImage.readjustSize(); 
        }
    }

    /** This method is called immediately before the text is rendered. The intent of
     *  'formatText' is to be overridden in a subclass, so that you can provide custom
     *  formatting for the TextField. In the overriden method, call 'setFormat' (either
     *  over a range of characters or the complete TextField) to modify the format to
     *  your needs.
     *  
     *  @param textField:  the openfl.text.TextField object that you can format.
     *  @param textFormat: the default text format that's currently set on the text field.
     */
    private function formatText(textField:openfl.text.TextField, textFormat:TextFormat):Void {}

    private function renderText(scale:Float, resultTextBounds:Rectangle):BitmapData
    {
        var width:Float  = mHitArea.width  * scale;
        var height:Float = mHitArea.height * scale;
        var hAlign:String = mHAlign;
        var vAlign:String = mVAlign;
        
        if (isHorizontalAutoSize)
        {
            width = Max.INT_MAX_VALUE;
            hAlign = HAlign.LEFT;
        }
        if (isVerticalAutoSize)
        {
            height = Max.INT_MAX_VALUE;
            vAlign = VAlign.TOP;
        }

        var hAlign_openfl:TextFormatAlign;
        switch(hAlign)
        {
        case HAlign.LEFT: hAlign_openfl = TextFormatAlign.LEFT;
        case HAlign.CENTER: hAlign_openfl = TextFormatAlign.CENTER;
        case HAlign.RIGHT: hAlign_openfl = TextFormatAlign.RIGHT;
        default: hAlign_openfl = TextFormatAlign.LEFT;
        }

        var textFormat:TextFormat = new TextFormat(mFontName, 
            mFontSize * scale, mColor, mBold, mItalic, mUnderline, null, null, hAlign_openfl);
        textFormat.kerning = mKerning;
        
        sNativeTextField.defaultTextFormat = textFormat;
        sNativeTextField.width = width;
        sNativeTextField.height = height;
        sNativeTextField.antiAliasType = AntiAliasType.ADVANCED;
        sNativeTextField.selectable = false;            
        sNativeTextField.multiline = true;            
        sNativeTextField.wordWrap = true;            
        sNativeTextField.text = mText;
        sNativeTextField.embedFonts = true;
        sNativeTextField.filters = mNativeFilters;
        
        // we try embedded fonts first, non-embedded fonts are just a fallback
        if (sNativeTextField.textWidth == 0.0 || sNativeTextField.textHeight == 0.0)
            sNativeTextField.embedFonts = false;
        
        formatText(sNativeTextField, textFormat);
        
        if (mAutoScale)
            autoScaleNativeTextField(sNativeTextField);
        
        var textWidth:Float  = sNativeTextField.textWidth;
        var textHeight:Float = sNativeTextField.textHeight;

        if (isHorizontalAutoSize)
            sNativeTextField.width = width = Math.ceil(textWidth + 5);
        if (isVerticalAutoSize)
            sNativeTextField.height = height = Math.ceil(textHeight + 4);
        
        // avoid invalid texture size
        if (width  < 1) width  = 1.0;
        if (height < 1) height = 1.0;
        
        var textOffsetX:Float = 0.0;
        if (hAlign == HAlign.LEFT)        textOffsetX = 2; // flash adds a 2 pixel offset
        else if (hAlign == HAlign.CENTER) textOffsetX = (width - textWidth) / 2.0;
        else if (hAlign == HAlign.RIGHT)  textOffsetX =  width - textWidth - 2;

        var textOffsetY:Float = 0.0;
        if (vAlign == VAlign.TOP)         textOffsetY = 2; // flash adds a 2 pixel offset
        else if (vAlign == VAlign.CENTER) textOffsetY = (height - textHeight) / 2.0;
        else if (vAlign == VAlign.BOTTOM) textOffsetY =  height - textHeight - 2;
        
        // if 'nativeFilters' are in use, the text field might grow beyond its bounds
        var filterOffset:Point = calculateFilterOffset(sNativeTextField, hAlign, vAlign);
        
        // finally: draw text field to bitmap data
        var bitmapData:BitmapData = new BitmapData(Std.int(width), Std.int(height), true, 0x0);
        var drawMatrix:Matrix = new Matrix(1, 0, 0, 1,
            filterOffset.x, filterOffset.y + Std.int(textOffsetY)-2);
        //var drawWithQualityFunc:Function = 
        //    "drawWithQuality" in bitmapData ? bitmapData["drawWithQuality"] : null;
        
        // Beginning with AIR 3.3, we can force a drawing quality. Since "LOW" produces
        // wrong output oftentimes, we force "MEDIUM" if possible.
        
        //if (Std.is(drawWithQualityFunc, Function))
        //    drawWithQualityFunc.call(bitmapData, sNativeTextField, drawMatrix, 
        //                             null, null, null, false, StageQuality.MEDIUM);
        //else
            bitmapData.draw(sNativeTextField, drawMatrix);
        
        sNativeTextField.text = "";
        
        // update textBounds rectangle
        resultTextBounds.setTo((textOffsetX + filterOffset.x) / scale,
                               (textOffsetY + filterOffset.y) / scale,
                               textWidth / scale, textHeight / scale);
        
        return bitmapData;
    }
    
    private function autoScaleNativeTextField(textField:openfl.text.TextField):Void
    {
        var size:Float   = textField.defaultTextFormat.size;
        var maxHeight:Int = Std.int(textField.height - 4);
        var maxWidth:Int  = Std.int(textField.width - 4);
        
        while (textField.textWidth > maxWidth || textField.textHeight > maxHeight)
        {
            if (size <= 4) break;
            
            var format:TextFormat = textField.defaultTextFormat;
            format.size = size--;
            textField.setTextFormat(format);
        }
    }
    
    private function calculateFilterOffset(textField:openfl.text.TextField,
                                           hAlign:String, vAlign:String):Point
    {
        var resultOffset:Point = new Point();
        var filters:Array<Dynamic> = textField.filters;
        
        if (filters != null && filters.length > 0)
        {
            var textWidth:Float  = textField.textWidth;
            var textHeight:Float = textField.textHeight;
            var bounds:Rectangle  = new Rectangle();
            
            for(filter in filters)
            {
                var blurX:Float = 0;
                var blurY:Float = 0;
                var angleDeg:Float = 0;
                var distance:Float = 0;
                if (Std.is(filter, BlurFilter))
                {
                    var f:BlurFilter = cast(filter, BlurFilter);
                    blurX = f.blurX;
                    blurY = f.blurY; 
                }
                else if (Std.is(filter, DropShadowFilter))
                {
                    var f:DropShadowFilter = cast(filter, DropShadowFilter);
                    blurX = f.blurX;
                    blurY = f.blurY;
                }
                var angle:Float = MathUtil.deg2rad(angleDeg);
                var marginX:Float = blurX * 1.33; // that's an empirical value
                var marginY:Float = blurY * 1.33;
                var offsetX:Float  = Math.cos(angle) * distance - marginX / 2.0;
                var offsetY:Float  = Math.sin(angle) * distance - marginY / 2.0;
                var filterBounds:Rectangle = new Rectangle(
                    offsetX, offsetY, textWidth + marginX, textHeight + marginY);
                
                bounds = bounds.union(filterBounds);
            }
            
            if (hAlign == HAlign.LEFT && bounds.x < 0)
                resultOffset.x = -bounds.x;
            else if (hAlign == HAlign.RIGHT && bounds.y > 0)
                resultOffset.x = -(bounds.right - textWidth);
            
            if (vAlign == VAlign.TOP && bounds.y < 0)
                resultOffset.y = -bounds.y;
            else if (vAlign == VAlign.BOTTOM && bounds.y > 0)
                resultOffset.y = -(bounds.bottom - textHeight);
        }
        
        return resultOffset;
    }
    
    // bitmap font composition
    
    private function createComposedContents():Void
    {
        if (mImage != null) 
        {
            mImage.removeFromParent(true); 
            mImage.texture.dispose();
            mImage = null; 
        }
        
        if (mQuadBatch == null) 
        { 
            mQuadBatch = new QuadBatch(); 
            mQuadBatch.touchable = false;
            addChild(mQuadBatch); 
        }
        else
            mQuadBatch.reset();
        
        var bitmapFont:BitmapFont = getBitmapFont(mFontName);
        if (bitmapFont == null) throw new Error("Bitmap font not registered: " + mFontName);
        
        var width:Float  = mHitArea.width;
        var height:Float = mHitArea.height;
        var hAlign:String = mHAlign;
        var vAlign:String = mVAlign;
        
        if (isHorizontalAutoSize)
        {
            width = Max.INT_MAX_VALUE;
            hAlign = HAlign.LEFT;
        }
        if (isVerticalAutoSize)
        {
            height = Max.INT_MAX_VALUE;
            vAlign = VAlign.TOP;
        }
        
        bitmapFont.fillQuadBatch(mQuadBatch,
            width, height, mText, mFontSize, mColor, hAlign, vAlign, mAutoScale, mKerning);
        
        mQuadBatch.batchable = mBatchable;
        
        if (mAutoSize != TextFieldAutoSize.NONE)
        {
            mTextBounds = mQuadBatch.getBounds(mQuadBatch, mTextBounds);
            
            if (isHorizontalAutoSize)
                mHitArea.width  = mTextBounds.x + mTextBounds.width;
            if (isVerticalAutoSize)
                mHitArea.height = mTextBounds.y + mTextBounds.height;
        }
        else
        {
            // hit area doesn't change, text bounds can be created on demand
            mTextBounds = null;
        }
    }
    
    // helpers
    
    private function updateBorder():Void
    {
        if (mBorder == null) return;
        
        var width:Float  = mHitArea.width;
        var height:Float = mHitArea.height;
        
        var topLine:Quad    = cast(mBorder.getChildAt(0), Quad);
        var rightLine:Quad  = cast(mBorder.getChildAt(1), Quad);
        var bottomLine:Quad = cast(mBorder.getChildAt(2), Quad);
        var leftLine:Quad   = cast(mBorder.getChildAt(3), Quad);
        
        topLine.width    = width; topLine.height    = 1;
        bottomLine.width = width; bottomLine.height = 1;
        leftLine.width   = 1;     leftLine.height   = height;
        rightLine.width  = 1;     rightLine.height  = height;
        rightLine.x  = width  - 1;
        bottomLine.y = height - 1;
        topLine.color = rightLine.color = bottomLine.color = leftLine.color = mColor;
    }
    
    // properties
    
    private var isHorizontalAutoSize(get, never):Bool;
    private function get_isHorizontalAutoSize():Bool
    {
        return mAutoSize == TextFieldAutoSize.HORIZONTAL || 
               mAutoSize == TextFieldAutoSize.BOTH_DIRECTIONS;
    }
    
    private var isVerticalAutoSize(get, never):Bool;
    private function get_isVerticalAutoSize():Bool
    {
        return mAutoSize == TextFieldAutoSize.VERTICAL || 
               mAutoSize == TextFieldAutoSize.BOTH_DIRECTIONS;
    }
    
    /** Returns the bounds of the text within the text field. */
    public var textBounds(get, never):Rectangle;
    private function get_textBounds():Rectangle
    {
        if (mRequiresRedraw) redraw();
        if (mTextBounds == null) mTextBounds = mQuadBatch.getBounds(mQuadBatch);
        return mTextBounds.clone();
    }
    
    /** @inheritDoc */
    public override function getBounds(targetSpace:DisplayObject, resultRect:Rectangle=null):Rectangle
    {
        if (mRequiresRedraw) redraw();
        getTransformationMatrix(targetSpace, sHelperMatrix);
        return RectangleUtil.getBounds(mHitArea, sHelperMatrix, resultRect);
    }
    
    /** @inheritDoc */
    public override function hitTest(localPoint:Point, forTouch:Bool=false):DisplayObject
    {
        if (forTouch && (!visible || !touchable)) return null;
        else if (mHitArea.containsPoint(localPoint)) return this;
        else return null;
    }

    /** @inheritDoc */
    public override function set_width(value:Float):Float
    {
        // different to ordinary display objects, changing the size of the text field should 
        // not change the scaling, but make the texture bigger/smaller, while the size 
        // of the text/font stays the same (this applies to the height, as well).
        
        mHitArea.width = value;
        mRequiresRedraw = true;
        return super.get_width();
    }
    
    /** @inheritDoc */
    public override function set_height(value:Float):Float
    {
        mHitArea.height = value;
        mRequiresRedraw = true;
        return super.get_height();
    }
    
    /** The displayed text. */
    public var text(get, set):String;
    private function get_text():String { return mText; }
    private function set_text(value:String):String
    {
        if (value == null) value = "";
        if (mText != value)
        {
            mText = value;
            mRequiresRedraw = true;
        }
        return mText;
    }
    
    /** The name of the font (true type or bitmap font). */
    public var fontName(get, set):String;
    private function get_fontName():String { return mFontName; }
    private function set_fontName(value:String):String
    {
        if (mFontName != value)
        {
            if (value == BitmapFont.MINI && bitmapFonts[value] == null)
                registerBitmapFont(new BitmapFont());
            
            mFontName = value;
            mRequiresRedraw = true;
            mIsRenderedText = getBitmapFont(value) == null;
        }
        return mFontName;
    }
    
    /** The size of the font. For bitmap fonts, use <code>BitmapFont.NATIVE_SIZE</code> for 
     *  the original size. */
    public var fontSize(get, set):Float;
    private function get_fontSize():Float { return mFontSize; }
    private function set_fontSize(value:Float):Float
    {
        if (mFontSize != value)
        {
            mFontSize = value;
            mRequiresRedraw = true;
        }
        return mFontSize;
    }
    
    /** The color of the text. For bitmap fonts, use <code>Color.WHITE</code> to use the
     *  original, untinted color. @default black */
    public var color(get, set):UInt;
    private function get_color():UInt { return mColor; }
    private function set_color(value:UInt):UInt
    {
        if (mColor != value)
        {
            mColor = value;
            mRequiresRedraw = true;
        }
        return mColor;
    }
    
    /** The horizontal alignment of the text. @default center @see starling.utils.HAlign */
    public var hAlign(get, set):String;
    private function get_hAlign():String { return mHAlign; }
    private function set_hAlign(value:String):String
    {
        if (!HAlign.isValid(value))
            throw new ArgumentError("Invalid horizontal align: " + value);
        
        if (mHAlign != value)
        {
            mHAlign = value;
            mRequiresRedraw = true;
        }
        return mHAlign;
    }
    
    /** The vertical alignment of the text. @default center @see starling.utils.VAlign */
    public var vAlign(get, set):String;
    private function get_vAlign():String { return mVAlign; }
    private function set_vAlign(value:String):String
    {
        if (!VAlign.isValid(value))
            throw new ArgumentError("Invalid vertical align: " + value);
        
        if (mVAlign != value)
        {
            mVAlign = value;
            mRequiresRedraw = true;
        }
        return mVAlign;
    }
    
    /** Draws a border around the edges of the text field. Useful for visual debugging. 
     *  @default false */
    public var border(get, set):Bool;
    private function get_border():Bool { return mBorder != null; }
    private function set_border(value:Bool):Bool
    {
        if (value && mBorder == null)
        {                
            mBorder = new Sprite();
            addChild(mBorder);
            
            for (i in 0 ... 4)
            {
                mBorder.addChild(new Quad(1.0, 1.0));
                //++i; // TODO: ?
            }
            
            updateBorder();
        }
        else if (!value && mBorder != null)
        {
            mBorder.removeFromParent(true);
            mBorder = null;
        }
        return mBorder != null;
    }
    
    /** Indicates whether the text is bold. @default false */
    public var bold(get, set):Bool;
    private function get_bold():Bool { return mBold; }
    private function set_bold(value:Bool):Bool 
    {
        if (mBold != value)
        {
            mBold = value;
            mRequiresRedraw = true;
        }
        return mBold;
    }
    
    /** Indicates whether the text is italicized. @default false */
    public var italic(get, set):Bool;
    private function get_italic():Bool { return mItalic; }
    private function set_italic(value:Bool):Bool
    {
        if (mItalic != value)
        {
            mItalic = value;
            mRequiresRedraw = true;
        }
        return mItalic;
    }
    
    /** Indicates whether the text is underlined. @default false */
    public var underline(get, set):Bool;
    private function get_underline():Bool { return mUnderline; }
    private function set_underline(value:Bool):Bool
    {
        if (mUnderline != value)
        {
            mUnderline = value;
            mRequiresRedraw = true;
        }
        return mUnderline;
    }
    
    /** Indicates whether kerning is enabled. @default true */
    public var kerning(get, set):Bool;
    private function get_kerning():Bool { return mKerning; }
    private function set_kerning(value:Bool):Bool
    {
        if (mKerning != value)
        {
            mKerning = value;
            mRequiresRedraw = true;
        }
        return mKerning;
    }
    
    /** Indicates whether the font size is scaled down so that the complete text fits
     *  into the text field. @default false */
    public var autoScale(get, set):Bool;
    private function get_autoScale():Bool { return mAutoScale; }
    private function set_autoScale(value:Bool):Bool
    {
        if (mAutoScale != value)
        {
            mAutoScale = value;
            mRequiresRedraw = true;
        }
        return mAutoScale;
    }
    
    /** Specifies the type of auto-sizing the TextField will do.
     *  Note that any auto-sizing will make auto-scaling useless. Furthermore, it has 
     *  implications on alignment: horizontally auto-sized text will always be left-, 
     *  vertically auto-sized text will always be top-aligned. @default "none" */
    public var autoSize(get, set):String;
    private function get_autoSize():String { return mAutoSize; }
    private function set_autoSize(value:String):String
    {
        if (mAutoSize != value)
        {
            mAutoSize = value;
            mRequiresRedraw = true;
        }
        return autoSize;
    }
    
    /** Indicates if TextField should be batched on rendering. This works only with bitmap
     *  fonts, and it makes sense only for TextFields with no more than 10-15 characters.
     *  Otherwise, the CPU costs will exceed any gains you get from avoiding the additional
     *  draw call. @default false */
    public var batchable(get, set):Bool;
    private function get_batchable():Bool { return mBatchable; }
    private function set_batchable(value:Bool):Bool
    { 
        mBatchable = value;
        if (mQuadBatch != null) mQuadBatch.batchable = value;
        return mBatchable;
    }

    /** The native Flash BitmapFilters to apply to this TextField. 
     *  Only available when using standard (TrueType) fonts! */
    public var nativeFilters(get, set):Array<BitmapFilter>;
    private function get_nativeFilters():Array<BitmapFilter> { return mNativeFilters; }
    private function set_nativeFilters(value:Array<BitmapFilter>) : Array<BitmapFilter>
    {
        if (!mIsRenderedText)
            throw(new Error("The TextField.nativeFilters property cannot be used on Bitmap fonts."));
        
        mNativeFilters = value.copy();
        mRequiresRedraw = true;
        return mNativeFilters;
    }
    
    /** The Context3D texture format that is used for rendering of all TrueType texts.
     *  The default (<pre>Context3DTextureFormat.BGRA_PACKED</pre>) provides a good
     *  compromise between quality and memory consumption; use <pre>BGRA</pre> for
     *  the highest quality. */
    public static var defaultTextureFormat(get, set):String;
    public static function get_defaultTextureFormat():String { return sDefaultTextureFormat; }
    public static function set_defaultTextureFormat(value:String):String
    {
        return sDefaultTextureFormat = value;
    }
    
    /** Makes a bitmap font available at any TextField in the current stage3D context.
     *  The font is identified by its <code>name</code> (not case sensitive).
     *  Per default, the <code>name</code> property of the bitmap font will be used, but you 
     *  can pass a custom name, as well. @return the name of the font. */
    public static function registerBitmapFont(bitmapFont:BitmapFont, name:String=null):String
    {
        if (name == null) name = bitmapFont.name;
        bitmapFonts[name.toLowerCase()] = bitmapFont;
        return name;
    }
    
    /** Unregisters the bitmap font and, optionally, disposes it. */
    public static function unregisterBitmapFont(name:String, dispose:Bool=true):Void
    {
        name = name.toLowerCase();
        
        if (dispose && bitmapFonts[name] != null)
            bitmapFonts[name].dispose();
        
        bitmapFonts.remove(name);
    }
    
    /** Returns a registered bitmap font (or null, if the font has not been registered). 
     *  The name is not case sensitive. */
    public static function getBitmapFont(name:String):BitmapFont
    {
        return bitmapFonts[name.toLowerCase()];
    }
    
    /** Stores the currently available bitmap fonts. Since a bitmap font will only work
     *  in one Stage3D context, they are saved in Starling's 'contextData' property. */
    private static var bitmapFonts(get, never):Map<String, BitmapFont>;
    private static function get_bitmapFonts():Map<String, BitmapFont>
    {
        var fonts:Map<String, BitmapFont> = Starling.current.bitmapFonts;
        
        if (fonts == null)
        {
            fonts = new Map<String, BitmapFont>();
            Starling.current.bitmapFonts = fonts;
        }
        
        return fonts;
    }
}
