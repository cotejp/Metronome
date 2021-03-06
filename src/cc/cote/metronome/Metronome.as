package cc.cote.metronome
{
	
	import flash.errors.IllegalOperationError;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.SampleDataEvent;
	import flash.media.Sound;
	import flash.media.SoundChannel;
	import flash.media.SoundTransform;
	import flash.utils.ByteArray;
	
	/**
	 * Dispatched when the metronome starts.
	 * 
	 * @eventType cc.cote.metronome.MetronomeEvent.START
	 */
	[Event(name="start", type="cc.cote.metronome.MetronomeEvent")]
	
	/**
	 * Dispatched each time the metronome ticks.
	 * 
	 * @eventType cc.cote.metronome.MetronomeEvent.TICK
	 */
	[Event(name="tick", type="cc.cote.metronome.MetronomeEvent")]
	
	/**
	 * Dispatched when the metronome stops.
	 * 
	 * @eventType cc.cote.metronome.MetronomeEvent.STOP
	 */
	[Event(name="stop", type="cc.cote.metronome.MetronomeEvent")]
	
	/**
	 * The <code>Metronome</code> class plays a beep sound (optional) and dispatches events at  
	 * regular intervals in a fashion similar to ActionScript's native <code>Timer</code> object. 
	 * However, unlike the <code>Timer</code> class, the <code>Metronome</code> class is not 
	 * affected by the runtime's frame rate. This makes it more precise and prevents the drifting 
	 * problem that occurs over time with a <code>Timer</code> object.
	 * 
	 * <p>At a moderate tempo, our tests show that the accuracy of the metronome is within ±0.03% 
	 * which is comparable to off-the-shelf consumer electronic metronomes and much better than 
	 * mechanical ones.</p>
	 * 
	 * <p>Using it is very simple. Simply instantiate it with the needed tempo and start it:</p>
	 * 
	 * <listing version="3.0">
	 * var metro:Metronome = new Metronome(140);
	 * metro.start();</listing>
	 * 
	 * <p>If you want to perform your own tasks when it ticks, listen to the 
	 * <code>MetronomeEvent.TICK</code> event:</p>
	 * 
	 * <listing version="3.0">
	 * var metro:Metronome = new Metronome(140);
	 * metro.addEventListener(MetronomeEvent.TICK, onTick);
	 * metro.start();
	 * 
	 * public function onTick(e:MetronomeEvent):void {
	 * 	trace(e);
	 * }</listing>
	 * 
	 * <p>If you want to use the <code>Metronome</code> more like a (more accurate) timer, you can 
	 * define the interval in milliseconds (instead of BPMs), silence it and assign a predetermined 
	 * number of ticks after which it should stop:</p>
	 * 
	 * <listing version="3.0">
	 * var metro:Metronome = new Metronome();
	 * metro.interval = 1000;
	 * metro.volume = 0;
	 * metro.maxTickCount = 5;
	 * metro.addEventListener(MetronomeEvent.TICK, onTick);
	 * metro.addEventListener(MetronomeEvent.STOP, onTick);
	 * metro.start();
	 * 
	 * public function onTick(e:MetronomeEvent):void {
	 *     trace(e);
	 * }</listing>
	 * 
	 * <p><b>The extraPrecise property</b></p>
	 * 
	 * <p>By default, the <code>extraPrecise</code> property of the <code>Metronome</code> is set to
	 * false. This should be fine in all but the most demanding cases. If you do need a little extra 
	 * accuracy, beware that the CPU usage will be higher.</p>
	 * 
	 * <p>The other edge case where you would need to set the <code>extraPrecise</code> property to
	 * <code>true</code> is if you want to use a BPM that is lower than 12 beats per seconds (or an 
	 * interval that is longer than 5000 milliseconds).</p>
	 * 
	 * <p><b>Using in Flash Pro</b></p>
	 * 
	 * <p>This library uses sound assets embedded with the <code>[Embed]</code> instruction. This 
	 * will work fine in FlashBuilder (and tools that use a similar compiler) but might give you 
	 * problems in Flash Pro. If you are using Flash Pro, you should simply link the 
	 * <code>Metronome.swc</code> file to avoid any issues.</p>
	 * 
	 * <p><b>Requirements</b></p>
	 * 
	 * <p>Because it uses the <code>SampleDataEvent</code> class of the Sound API, the 
	 * <code>Metronome</code> class only works in Flash Player 10+ and AIR 1.5+. Also, the system
	 * must have a sound card and one free available sound channel.</p>
	 * 
	 * @see cc.cote.metronome.MetronomeEvent
	 * @see http://cote.cc/projects/metronome
	 * @see http://github.com/cotejp/Metronome
	 */
	public class Metronome extends EventDispatcher
	{
		
		/** Version string of this release */
		public static const VERSION:String = '1.0b rev1';
		
		/** The maximum sound sample rate available in ActionScript (in Hertz). */
		public static const SAMPLE_RATE:uint = 44100;
		
		/**
		 * Max number of samples that can be written to the audio buffer at once. The minimum is
		 * 2048. Below that, the channel will trigger a SOUND_COMPLETE event.
		 * @private 
		 */
		private const MAX_BUFFER_SAMPLES:uint = 8192;
		
		[Embed(source='/cc/cote/metronome/sounds/Sine880Hz.mp3')] private var NormalBeep:Class;
		[Embed(source='/cc/cote/metronome/sounds/Sine1760Hz.mp3')] private var AccentedBeep:Class;
		[Embed(source='/cc/cote/metronome/sounds/Silence.mp3')] private var Reference:Class;
		
		private var _tempo:Number = 120;
		private var _interval:Number = 500.0;
		private var _startTime:Number = NaN;
		private var _lastTickTime:Number = NaN;
		private var _ticks:uint = 0;
		private var _regularBeep:Sound = new NormalBeep();
		private var _accentedBeep:Sound = new AccentedBeep();
		private var _soundReference:Sound = new Reference();
		private var _soundChannel:SoundChannel;
		private var _samplesBeforeTick:uint;
		private var _running:Boolean = false;
		private var _missed:uint = 0;
		private var _maxTickCount:uint = 0;
		private var _extraPrecise:Boolean = false;
		private var _ba:ByteArray = new ByteArray();
		private var _regularBeepTransform:SoundTransform = new SoundTransform();
		private var _accentedBeepTransform:SoundTransform = new SoundTransform();
		private var _pattern:Array = [];
		
		/**
		 * Constructs a new <code>Metronome</code> object, pre-set at the desired tempo and volume.
		 * 
		 * @param tempo 		The tempo to set the Metronome to (can be altered anytime with the 
		 * 						'tempo' property).
		 * @param volume		The volume of the beep sounds.
		 * @param pattern		This array tells the metronome when it should play the accented beep
		 * 						sound instead of the regular beep sound. See the documentation of 
		 * 						the <code>pattern</code> property for more details. By default an
		 * 						empty array is used meaning no beeps will be accented.
		 * @param maxTickCount	The maximum number ot ticks to trigger. The default (0) means no 
		 * 						maximum.
		 */
		public function Metronome(
			tempo:uint = 120, volume:Number = 1.0, pattern:Array = null, maxTickCount:uint = 0
		) {
			this.tempo = tempo;
			this.volume = volume;
			if (pattern) _pattern = pattern;
			_maxTickCount = maxTickCount;
			_ba.length = MAX_BUFFER_SAMPLES * 4 * 2; 	// Samples are 32bits floats (1byte x4) and stereo (x2)
		}
		
		/**
		 * Starts the metronome. <code>MetronomeEvent.TICK</code> will be dispatched each time the 
		 * <code>Metronome</code> ticks. Beeps will sound if the <code>silent</code> property is 
		 * <code>false</code>.
		 */
		public function start():void {
			_running = true;
			_ticks = 0;
			_missed = 0;
			if (_extraPrecise) _initializePreciseMode();
			_startTime = new Date().getTime();
			_tick();
		}
		
		/** @private */
		private function _initializePreciseMode():void {
			_samplesBeforeTick = Math.round(_interval / 1000 * SAMPLE_RATE);
			_soundReference.addEventListener(
				SampleDataEvent.SAMPLE_DATA, _onSampleData, false, 0, true
			);
		}
		
		/**
		 * Stops the metronome.
		 */
		public function stop():void {
			if ( _soundReference.hasEventListener(SampleDataEvent.SAMPLE_DATA) ) {
				_soundReference.removeEventListener(SampleDataEvent.SAMPLE_DATA, _onSampleData);
			}
			_running = false;
			_soundChannel.removeEventListener(Event.SOUND_COMPLETE, _tick);
			_soundChannel.stop();
			dispatchEvent( new MetronomeEvent(MetronomeEvent.STOP, _ticks, _lastTickTime) );
			_samplesBeforeTick = 0;
		}
		
		/** @private */
		private function _onSampleData(e:SampleDataEvent):void {
			
//			if (_audioSyncChannel) {
//				// Latency in milliseconds
//				var latency:Number = (e.position / 44100 / 1000) - _audioSyncChannel.position + _interval;
//				if (latency > 0) _samplesBeforeTick -= Math.round(latency / 1000 * 44100);
//				trace(latency);
//			}
			
			if (_samplesBeforeTick >= MAX_BUFFER_SAMPLES) {
				e.data.writeBytes(_ba);
				_samplesBeforeTick -= MAX_BUFFER_SAMPLES;
			} else if (_samplesBeforeTick > 0) {
				e.data.writeBytes(_ba, 0, _samplesBeforeTick * 4 * 2);
				_samplesBeforeTick = 0;
			}
			
		}
		
		/** @private */
		private function _tick(e:Event = null):void {
			
			// If metronome has been stopped, we shouldn't continue dispatching events
			if (! _running) return;
			
			//trace(new Date().getTime() - (_startTime + _interval * (_ticks - 1)) - _interval);
			
			// Jot down current tick info and dispatch event (tick is dispatched all the time while
			// start is dispatched only the first time)
			_lastTickTime = new Date().getTime();
			_ticks++;
			if (_ticks == 1) {
				dispatchEvent( new MetronomeEvent(MetronomeEvent.START, 0, _lastTickTime));
			}
			dispatchEvent( new MetronomeEvent(MetronomeEvent.TICK, _ticks, _lastTickTime));
			
			// Play audible beeps if requested (according to the specified pattern)
			var ch:SoundChannel;
			var pos:uint = (_ticks - 1) % _pattern.length;
			
			if (!isNaN(pos) && _pattern[pos]) {
				if (_accentedBeepTransform.volume > 0) {
					ch = _accentedBeep.play();
					ch.soundTransform = _accentedBeepTransform;
				}
			} else {
				if (_regularBeepTransform.volume > 0) {
					ch = _regularBeep.play();
					ch.soundTransform = _regularBeepTransform;
				}
			}
			
			// Check if _maxTickCount would be exceeded by scheduling another tick
			if (_ticks >= _maxTickCount && _maxTickCount != 0) {
				stop();
				return;
			}
			
			// Calculate the interval before next tick. If the interval is negative (meaning it 
			// should have been triggered already but was delayed because the cpu was overloaded), 
			// tick right away (in the hopes of catching up). That's the best we can do in this kind 
			// of situation.
			var delay:Number = _startTime + (_ticks * _interval) - _lastTickTime;
			if (delay <= 10) {
				_missed++;
				_tick();
				return;
			}
			
			if (_extraPrecise) {
				_samplesBeforeTick = delay / 1000 * SAMPLE_RATE;
				_soundChannel = _soundReference.play();
			} else {
				_soundChannel = _soundReference.play(_soundReference.length - delay);				
			}
			
			if (_soundChannel) {
				// Cannot use weak listener here (&*?%). I don't know why.
				_soundChannel.addEventListener(Event.SOUND_COMPLETE, _tick);
			} else {
				throw new IllegalOperationError(
					"To use the Metronome class, you need a sound card and at least one free " +
					"sound channel."
				);
			}
			
		}
		
		/**
		 * The current tempo of the metronome in beats per minute. The tempo must be 12 or greater 
		 * and less than 600 beats per minute. If the <code>extraPrecise</code> property is set to
		 * <code>true</code>, you can define a tempo lower than 12. It can even be a fractional
		 * number, as long as its larger than 0.
		 * 
		 * @throws ArgumentError 	The tempo must be greater than 0 and less than 600 beats per 
		 * 							minute.
		 * @throws ArgumentError 	To use a tempo slower than 12 BPM, you must set "extraPrecise" 
		 * 							to true.
		 */
		public function get tempo():Number {
			return _tempo;
		}
		
		/** @private */
		public function set tempo(value:Number):void {
			
			if (value <= 0 || value > 600) {
				throw new ArgumentError(
					'The tempo must be greater than 0 and less than 600 beats per minute.'
				);
				return;
			} else if (!extraPrecise && value < 12) {
				throw new ArgumentError(
					'To use a tempo slower than 12 BPM, you must set "extraPrecise" to true.'
				);
				return;
			}
			
			_tempo = value;
			_interval = 60 / _tempo * 1000;
		}
		
		/**
		 * The interval (in milliseconds) between ticks. Modifying this value alters the tempo just
		 * as modifying the tempo alters the interval between ticks. The interval must be at least
		 * 100 milliseconds and at most 5000 milliseconds. If <code>extraPrecise</code> is set to 
		 * true, the interval can be as long as wanted.
		 * 
		 * @throws ArgumentError 	The interval must be at least 100 milliseconds long.
		 * @throws ArgumentError 	To use an interval longer than 5000 milliseconds, you must set 
		 * 							"extraPrecise" to true.
		 */
		public function get interval():uint {
			return _interval;
		}
		
		/** @private */
		public function set interval(value:uint):void {
			
			if (value < 100) {
				throw new ArgumentError('The interval must be at least 100 milliseconds long.');
				return
			} else if (!_extraPrecise && value > 5000) {
				throw new ArgumentError(
					'To use an interval longer than 5000 milliseconds, you must set "extraPrecise" to true.'
				);
				return;
			}
			
			_interval = value;
			_tempo = 60 / _interval * 1000;
		}
		
		/** 
		 * The time when the metronome was last started expressed as the number of milliseconds 
		 * elapsed since midnight on January 1st, 1970, universal time.
		 */
		public function get startTime():Number {
			return _startTime;
		}
		
		/**
		 * The number of times the metronome ticked. This number is reset on start but not on stop.
		 * This means you can retrieve the number of times it ticked even after it was stopped.
		 */
		public function get ticks():uint {
			return _ticks;
		}
		
//		/**
//		 * The base tells the <code>Metronome</code> when to play accented beeps. The accented 
//		 * beep is played once every n beats where n is the base. If you set the base to 1, all 
//		 * beeps will be accented. If you set the base to 0, no beat will be accented.
//		 */
//		public function get base():uint {
//			return _base;
//		}
//		
//		/** @private */
//		public function set base(value:uint):void {
//			_base = value;
//		}

		/** Indicates whether the metronome is currently running. */ 
		public function get running():Boolean {
			return _running;
		}

		/** 
		 * The number of times, since the metronome was started, that it couldn't properly schedule 
		 * a tick. This is typically caused by the processor being overloaded during one or a few 
		 * frames. If you get misses, make sure each frame's code is processed within the time it 
		 * has been allocated.
		 * 
		 * <p>For example, if you are running your application at 30 frames per second, each frame 
		 * has 33.3 milliseconds to complete its tasks. If it takes more than that, all processing 
		 * occuring after will be pushed back. In some instances (depending on frame rate and 
		 * metronome tempo), this could mean the processing of the Metronome events will be pushed 
		 * so far back that it will actually occur after a TICK should have been dispatched. If this 
		 * happens, the metronome will fire two or more TICKs back-to-back in order to stay in line 
		 * with the tempo.</p>
		 * 
		 * <p>Obviously, this is not desirable. The solution is to adjust your code so it stays
		 * within its allocated frame time (budget). You can verify that by using a tool such as 
		 * Adobe Scout.</p>
		 */
		public function get missed():uint {
			return _missed;
		}

		/**
		 * The beeping sound that plays for 'normal' beats. A 'normal' beat is one that falls on 
		 * beats not divisible by the <code>base</code> property. If you decide to use your own 
		 * sound, its duration should be shorter than the interval between two beats.
		 */
		public function get regularBeep():Sound {
			return _regularBeep;
		}
		
		/** @private */
		public function set regularBeep(value:Sound):void {
			_regularBeep = value;
		}

		/**
		 * The beeping sound that plays for 'accented' beats. An 'accented' beat is one that falls 
		 * on beats divisible by the <code>base</code> property. If you decide to use you own sound, 
		 * its duration should be shorter than the interval between two beats.
		 */
		public function get accentedBeep():Sound {
			return _accentedBeep;
		}

		/** @private */
		public function set accentedBeep(value:Sound):void {
			_accentedBeep = value;
		}

		/** The maximum number of times the Metronome should tick. A value of 0 means no maximum. */
		public function get maxTickCount():uint {
			return _maxTickCount;
		}

		/** @private */
		public function set maxTickCount(value:uint):void {
			_maxTickCount = value;
		}

		/** 
		 * Indicates whether the <code>extraPrecise</code> mode is being used. By default, it is 
		 * not. When activated, the metronome gains a little more precision. However, 
		 * <code>extraPrecise</code> mode consumes more CPU cycles. Unless you really need the extra
		 * accuracy, you should leave it to false.
		 * 
		 * @throws IllegalOperationError 	The 'extraPecise' mode cannot be changed while the 
		 * 									Metronome is running
		 */
		public function get extraPrecise():Boolean {
			return _extraPrecise;
		}

		/** @private */
		public function set extraPrecise(value:Boolean):void {
			
			if (_running) {
				throw new IllegalOperationError(
					"The 'extraPecise' mode cannot be changed while the Metronome is running"
				);
				return;
			}
			
			_extraPrecise = value;
			
			if (_extraPrecise) {
				_soundReference = new Sound();
			} else {
				_soundReference = new Reference();
			}
			
		}
		
		/** 
		 * The overall volume of the metronome's beep sounds expressed as a number between 0 
		 * (minimum volume) and 1 (maximum volume). When set, it defines the volume of both the 
		 * regular beep sound and the accented beep sound. If you want to control them individually, 
		 * use the <code>regularBeepVolume</code> and <code>accentedBeepVolume</code> properties. 
		 */
		public function get volume():Number {
			return _regularBeepTransform.volume;
		}

		/** @private */
		public function set volume(value:Number):void {
			_regularBeepTransform.volume = value;
			_accentedBeepTransform.volume = value;
		}
		
		/** 
		 * The volume of the metronome's regular beep sound expressed as a number between 0 (minimum 
		 * volume) and 1 (maximum volume).
		 */
		public function get regularBeepVolume():Number {
			return _regularBeepTransform.volume;
		}

		/** @private */
		public function set regularBeepVolume(value:Number):void {
			_regularBeepTransform.volume = value;
		}
		
		/** 
		 * The volume of the metronome's accented beep sound expressed as a number between 0 
		 * (minimum volume) and 1 (maximum volume).
		 */
		public function get accentedBeepVolume():Number {
			return _accentedBeepTransform.volume;
		}

		/** @private */
		public function set accentedBeepVolume(value:Number):void {
			_accentedBeepTransform.volume = value;
		}

		/** 
		 * This array defines the beeps that will be accented by the metronome. Each entry in the 
		 * array is a boolean value. A 'true' value means the beep will be accented and a value of
		 * 'false' means it will not.
		 */
		public function get pattern():Array {
			return _pattern;
		}

		/** @private */
		public function set pattern(value:Array):void {
			_pattern = value;
		}
		
		
		
		
		
		
		
		
		
		
		
		/**
		 * IF WE EVER WANT TO DO AWAY WITH THE EXTERNAL SOUND FILE REFERENCEs, WE COULD USE THIS 
		 * CODE WHICH COMES FROM POPFORGE (ANDRE MICHELLE). IT ALLOWS FOR THE DYNAMIC CREATION OF 
		 * SOUND OBJECTS WITHOUT THE STUPID BUG THAT IS STILL PLAGUING THE loadPCMFromByteArray() 
		 * METHOD:
		 * 
		 * 		https://bugbase.adobe.com/index.cfm?event=bug&id=3707118
		 * 
		 * WE COULD DO AWAY WITH THE EMBEDDING OF THE BARE SWF BY ENCODING EACH OF ITS BYTE INTO A 
		 * STRING OF TWO-CHARACTERS HEX VALUES
		 * 
		 * [Embed(source="swf.bin", mimeType="application/octet-stream")] static private const SWF: Class;
		 * 
		 * Creates a flash.media.Sound object from dynamic audio material
		 * 
		 * @param samples A uncompressed PCM ByteArray
		 * @param channels Mono(1) or Stereo(2)
		 * @param bits 8bit(8) or 16bit(16)
		 * @param rate SamplingRate 5512Hz, 11025Hz, 22050Hz, 44100Hz
		 * @param onComplete Function, that will be called after the Sound object is created. The signature must accept the Sound object as a parameter!
		 * 
		 * @see http://livedocs.adobe.com/flex/2/langref/flash/media/Sound.html flash.media.Sound
		 */
//		static public function fromByteArray( bytes: ByteArray, channels: uint, bits: uint, rate: uint, onComplete: Function ): void
//		{
//			
//			//-- get naked swf bytearray
//			var swf: ByteArray = ByteArray( new SWF() );
//			
//			swf.endian = Endian.LITTLE_ENDIAN;
//			swf.position = swf.length;
//			
//			//-- write define sound tag header
//			swf.writeShort( 0x3bf );
//			swf.writeUnsignedInt( bytes.length + 7 );
//			
//			//-- assemble audio property byte (uncompressed little endian)
//			var byte2: uint = 3 << 4;
//			
//			switch( rate )
//			{
//				case 44100: byte2 |= 0xc; break;
//				case 22050: byte2 |= 0x8; break;
//				case 11025:	byte2 |= 0x4; break;
//			}
//			
//			var numSamples: int = bytes.length;
//			
//			if( channels == 2 )
//			{
//				byte2 |= 1;
//				numSamples >>= 1;
//			}
//			
//			if( bits == 16 )
//			{
//				byte2 |= 2;
//				numSamples >>= 1;
//			}
//			
//			//-- write define sound tag
//			swf.writeShort( 1 );
//			swf.writeByte( byte2 );
//			swf.writeUnsignedInt( numSamples );
//			swf.writeBytes( bytes );
//			
//			//-- write eof tag in swf stream
//			swf.writeShort( 1 << 6 );
//			
//			//-- overwrite swf length
//			swf.position = 4;
//			swf.writeUnsignedInt( swf.length );
//			swf.position = 0;
//			
//			var onSWFLoaded: Function = function( event: Event ): void
//			{
//				onComplete( Sound( new ( loader.contentLoaderInfo.applicationDomain.getDefinition( 'SoundItem' ) as Class )() ) );
//			}
//			
//			var loader: Loader = new Loader();
//			loader.contentLoaderInfo.addEventListener( Event.COMPLETE, onSWFLoaded );
//			loader.loadBytes( swf );
//		}
		
		
	}
	
}

