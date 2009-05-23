import org.xiph.system.Bytes;

import flash.Vector;
import flash.external.ExternalInterface;
import flash.events.Event;
import flash.events.ProgressEvent;
import org.xiph.fogg.SyncState;
import org.xiph.fogg.StreamState;
import org.xiph.fogg.Page;
import org.xiph.fogg.Packet;

import org.xiph.fvorbis.Info;
import org.xiph.fvorbis.Comment;
import org.xiph.fvorbis.DspState;
import org.xiph.fvorbis.Block;

import org.xiph.foggy.Demuxer;
//import org.xiph.foggy.DemuxerStatus;

import org.xiph.system.AudioSink;

class PAudioSink extends AudioSink {
    /**
       A very quick&dirty wrapper around the AudioSink to somewhat
       make up for the lack of a proper demand-driven ogg demuxer a.t.m.
     */

    var cb_threshold : Int;
    var cb_pending : Bool;
    var cb : PAudioSink -> Void;

    public function new(chunk_size : Int, fill = true, trigger = 0) {
        super(chunk_size, fill, trigger);
        cb_threshold = 0;
        cb = null;
        cb_pending = false;

    }

    public function set_cb(threshold : Int, cb : PAudioSink -> Void) : Void {
        cb_threshold = threshold;
        this.cb = cb;
    }

    override function _data_cb(event : flash.events.SampleDataEvent) :Void {
        super._data_cb(event);

        if (cb_threshold > 0) {
            if (available < cb_threshold && !cb_pending) {
                cb_pending = true;
                haxe.Timer.delay(_delayed_cb, 1);
            }
        }
    }

    function _delayed_cb() : Void {
        this.cb_pending = false;
        this.cb(this);
    }

    override public function write(pcm : Array<Vector<Float>>,
                                   index : Vector<Int>, samples : Int) : Void {
        super.write(pcm, index, samples);

        if (cb_threshold > 0) {
            if (available < cb_threshold && !cb_pending) {
                cb_pending = true;
                haxe.Timer.delay(_delayed_cb, 1);
            }
        }
    }
}

class AnMp3Player {
    var mp3Sound:flash.media.Sound;
    var mp3Request:flash.net.URLRequest;
    var bIsPlaying: Bool;
    var onProgress:flash.events.ProgressEvent -> Void;
    var onID3:flash.events.Event -> Void;
    var statusCB : String -> Void;
    var bufferCB : Int -> Void;
    var newSongCB: String -> Void;
    var onError: flash.events.IOErrorEvent -> Void;
    var volume: Int;
    var sch:flash.media.SoundChannel;
    var onSoundComplete:Event -> Void;
    
    function DoProgress(event:ProgressEvent):Void {
    	if(mp3Sound.isBuffering)doBuffer(50)
        else {
      		if(!bIsPlaying){
      			doBuffer(100);
      			bIsPlaying=true;
      			doStatus("playing");
      		}	
        }
    }
    
    function doBuffer(value: Int) :Void {
            if(bufferCB != null) bufferCB(value);
    }
    
    
    
    
    function doStatus(state: String) :Void {
    	trace("mp3:"+state);
            if(statusCB != null) statusCB(state);
    }
    
    function DoSoundComplete(e:Event):Void {
        bIsPlaying=false;
        doStatus("stopped");
    }
    
    function DoID3(event:Event):Void {
    	var statstring: String;
    	statstring = "Artist"+ "=\""+StringTools.replace(mp3Sound.id3.artist,"\"","\"\"")+"\";";
    	statstring+="Title"+"=\""+StringTools.replace(mp3Sound.id3.songName,"\"","\"\"")+"\";";
    	statstring+="Album"+"=\""+StringTools.replace(mp3Sound.id3.album,"\"","\"\"")+"\";";
    	statstring+="Genre"+"=\""+StringTools.replace(mp3Sound.id3.genre,"\"","\"\"")+"\";";
    	if(newSongCB != null) newSongCB(statstring);
    }
    
    function DoError(event:flash.events.IOErrorEvent):Void {
    	doStatus("error=ioerror");
    	bIsPlaying=false;
    }
    
    public function setNewSongCB(newCB : String -> Void): Void {
            newSongCB = newCB;
    }
    //-----------------
    public function setBufferCB(newCB : Int -> Void): Void {
        bufferCB = newCB;
    }
        
    
    public function setStatusCB(newCB : String -> Void): Void {
        statusCB = newCB;
    }
    
    
    public function new() {
    	onProgress=DoProgress;
    	onID3=DoID3;
    	onError=DoError;
    	onSoundComplete=DoSoundComplete;
    	sch = null;
    }
    public function setVolume(vol:Int):Void {
    	var strans:flash.media.SoundTransform;
    	volume=vol;
    	if(sch != null) {
    		strans = sch.soundTransform;
		strans.volume = (volume+0.0001)/100;
    	   	sch.soundTransform = strans;
    	}
    
    }
    public function playMP3 ( murl:String):Void {
        trace("playMP3: "+murl);
        bIsPlaying = false;
        mp3Request = new flash.net.URLRequest(murl);
        mp3Sound = new flash.media.Sound();
        mp3Sound.load(mp3Request);
        mp3Sound.addEventListener(flash.events.ProgressEvent.PROGRESS, onProgress);
        mp3Sound.addEventListener(Event.ID3, onID3);
        mp3Sound.addEventListener(flash.events.IOErrorEvent.IO_ERROR, onError);
        sch = mp3Sound.play(0,0);
        sch.addEventListener(Event.SOUND_COMPLETE,onSoundComplete);
        doStatus("buffering");
        setVolume(volume);
    }
    
    public function stopMP3() :Void {
    	//trace(".mp3 stopping");
    	//doStatus("stopped");
    	bIsPlaying=false;
    	if(sch!= null)sch.stop();
    	
    	trace(" mp3 stopped");
    }
    public function isPlaying(): Bool {
    	return bIsPlaying;
    }
 
}

/* ANOnymous-delivered Ogg Player for ANOma.fm :3 */
class AnOggPlayer {
    var ul : flash.net.URLStream;
    var asink : PAudioSink;
    var url : String;
    var volume : Int;
    var mp3player:AnMp3Player;
    
    // FIXME: find a better way to initialize those static bits?
    static function init_statics() : Void {
        org.xiph.fogg.Buffer._s_init();
        org.xiph.fvorbis.FuncFloor._s_init();
        org.xiph.fvorbis.FuncMapping._s_init();
        org.xiph.fvorbis.FuncTime._s_init();
        org.xiph.fvorbis.FuncResidue._s_init();
    }

    var _packets : Int;
    var vi : Info;
    var vc : Comment;
    var vd : DspState;
    var vb : Block;
    var dmx : Demuxer;

    var _pcm : Array<Array<Vector<Float>>>;
    var _index : Vector<Int>;

    var read_pending : Bool;
    var read_started : Bool;

    function _proc_packet_head(p : Packet, sn : Int) : DemuxerStatus {
        vi.init();
        vc.init();
        if (vi.synthesis_headerin(vc, p) < 0) {
            // not vorbis - clean up and ignore
            vc.clear();
            vi.clear();
        } else {
            // vorbis - detach this cb and attach the main decoding cb
            // to the specific serialno
            //dmx.remove_packet_cb(-1);
            dmx.set_packet_cb(sn, _proc_packet);
        }
	_packets = 0;
        _packets++;
        return dmx_ok;
    }

    function _proc_packet(p : Packet, sn : Int) : DemuxerStatus {
        var samples : Int;

        switch(_packets) {
        case 0:
            /*
            vi.init();
            vc.init();
            if (vi.synthesis_headerin(vc, p) < 0) {
                return dmx_ok;
            } else {
                dmx.set_packet_cb(sn, _proc_packet);
                dmx.remove_packet_cb(-1);
            }
            */
        case 1:
            vi.synthesis_headerin(vc, p);

        case 2:
            vi.synthesis_headerin(vc, p);

            {
                var ptr : Array<Bytes> = vc.user_comments;
                var j : Int = 0;
                var comments : String;
                var comment: Array<String>;
                //trace("");
                comments="";
                while (j < ptr.length) {
                    if (ptr[j] == null) {
                        break;
                    };
                    comment = System.fromBytes(ptr[j], 0, ptr[j].length - 1).split("=");
                    comments = comments+comment[0];
                    comments = comments +"=\""+StringTools.replace(comment[1],"\"","\"\"")+"\";";
                    trace(System.fromBytes(ptr[j], 0, ptr[j].length - 1));
                    j++;
                };
                _doNewSong(comments);
		/*
                trace("Bitstream is " + vi.channels + " channel, " +
                      vi.rate + "Hz");
                trace(("Encoded by: " +
                       System.fromBytes(vc.vendor, 0, vc.vendor.length - 1)) +
                      "\n");*/
            }

            vd.synthesis_init(vi);
            vb.init(vd);

            _pcm = [null];
            _index = new Vector(vi.channels, true);

        default:
            if (vb.synthesis(p) == 0) {
                vd.synthesis_blockin(vb);
            }

            while ((samples = vd.synthesis_pcmout(_pcm, _index)) > 0) {
                asink.write(_pcm[0], _index, samples);
                vd.synthesis_read(samples);
            }
        }

        _packets++;

        return dmx_ok;
    }

    function _read_data() : Void {
        var to_read : Int = ul.bytesAvailable;
        var chunk : Int = 8192;
        //trace("read_data: " + ul.bytesAvailable+" to read: "+to_read);
        read_pending = false;

        if (to_read == 0)
            return;

        if (to_read < chunk && !read_pending) {
            read_pending = true;
            haxe.Timer.delay(_read_data, 50);
            return;
        }

        to_read = ul.bytesAvailable;
        if (to_read > chunk) {
            to_read = chunk;
        }

        dmx.read(ul, to_read);
    }

    function try_ogg() : Void {
        dmx = new Demuxer();

        vi = new Info();
        vc = new Comment();
        vd = new DspState();
        vb = new Block(vd);

        _packets = 0;

        dmx.set_packet_cb(-1, _proc_packet_head);

        //asink = new PAudioSink(8192, true, 132300);
        asink = new PAudioSink(8192, true, 132300);
        asink.setBufferCB(_doBuffer);
        asink.setStatusCB(_doState);
        asink.setVolume(volume);
        asink.set_cb(88200, _on_data_needed);
    }
    
    function _playURL ( murl:String ): Void {
    	trace("playURL: "+murl);
    	url=murl;
    	if(StringTools.endsWith(url,"ogg")||StringTools.endsWith(url,"OGG")||StringTools.endsWith(url,"Ogg")) {
    		_doState("buffering");
    		ul.load(new flash.net.URLRequest(url));
    	}
    	else if(StringTools.endsWith(url,"mp3")||StringTools.endsWith(url,"MP3")||StringTools.endsWith(url,"Mp3")) {
    		_playMP3(murl);
    	}
    }
    function _playMP3 (murl:String):Void {
    	trace("playing mp3");
    	mp3player = new AnMp3Player();
    	mp3player.setNewSongCB(_doNewSong);
    	mp3player.setStatusCB(_doState);
    	mp3player.setBufferCB(_doBuffer);
    	mp3player.playMP3(murl);
    }
    
    function _stopPlay() : Void {
    	trace("stopPlay!");
    	if(mp3player!=null){
	    		trace("stopping mp3");
	    		mp3player.stopMP3();
	    		
    	}
    	if(asink!=null) {
    		asink.stop();
    		ul.close();
    	}
    	
    	_doState("stopped");
    }
    
    function _setVolume(vol: Int) : Void {
    	volume = vol;
    	if(asink!=null) asink.setVolume(vol);
    	if(mp3player!=null)mp3player.setVolume(vol);
    }
    
    function _doState(state: String) : Void {
    	flash.external.ExternalInterface.call("onOggState",state);
    }
    
    function _doBuffer(fill : Int) : Void {
    	flash.external.ExternalInterface.call("onOggBuffer",fill);
    }
    
    function _doNewSong(headers:String) : Void {
    	flash.external.ExternalInterface.call("onOggSongBegin",headers);
    }
    
    function start_request() : Void {
        trace("Starting downloading: " + url);
        
        ul = new flash.net.URLStream();

        ul.addEventListener(flash.events.Event.OPEN, _on_open	);
        ul.addEventListener(flash.events.ProgressEvent.PROGRESS, _on_progress);
        ul.addEventListener(flash.events.Event.COMPLETE, _on_complete);
        ul.addEventListener(flash.events.IOErrorEvent.IO_ERROR, _on_error);
        ul.addEventListener(flash.events.SecurityErrorEvent.SECURITY_ERROR,
                            _on_security);
	_doState("loaded");
        //ul.load(new flash.net.URLRequest(url));
    }

    function _on_open(e : flash.events.Event) : Void {
        read_pending = false;
        read_started = false;
        try_ogg();
    }

    function _on_progress(e : flash.events.ProgressEvent) : Void {
        //trace("on_progress: " + ul.bytesAvailable);
        if (!read_started && ul.bytesAvailable > 8192) {
            _read_data();
        }
    }

    function _on_complete(e : flash.events.Event) : Void {
        //trace("Found ? pages with " + _packets + " packets.");
        trace("\n\n=====   Loading '" + url + "'done. Enjoy!   =====\n");
    }

    function _on_error(e : flash.events.IOErrorEvent) : Void {
        trace("error occured: " + e);
        _doState("error=ioerror");
    }

    function _on_security(e : flash.events.SecurityErrorEvent) : Void {
        trace("security error: " + e);
        _doState("error=securerror");
    }

    function _on_data_needed(s : PAudioSink) : Void {
         //trace("on_data: " + ul.bytesAvailable);
        read_started = true;
        _read_data();
      
    }


    static function check_version() : Bool {
        if (flash.Lib.current.loaderInfo.parameters.noversioncheck != null)
            return true;

        var vs : String = flash.system.Capabilities.version;
        var vns : String = vs.split(" ")[1];
        var vn : Array<String> = vns.split(",");

        if (vn.length < 1 || Std.parseInt(vn[0]) < 10)
            return false;

        if (vn.length < 2 || Std.parseInt(vn[1]) > 0)
            return true;

        if (vn.length < 3 || Std.parseInt(vn[2]) > 0)
            return true;

        if (vn.length < 4 || Std.parseInt(vn[3]) >= 525)
            return true;

        return false;
    }

    private function new(url : String) {
        this.url = url;
    }

    public static function main() : Void {
        if (check_version()) {
            init_statics();
	    
            var fvs : Dynamic<String> = flash.Lib.current.loaderInfo.parameters;
            var url = fvs.playUrl == null ? "http://anoma.ch:3210/low.ogg" : fvs.playUrl;

            var foe = new AnOggPlayer(url);
            foe.volume=100;
            flash.system.Security.allowDomain("anoma.ch");
            flash.external.ExternalInterface.addCallback("playURL",foe._playURL);
            flash.external.ExternalInterface.addCallback("stopPlay",foe._stopPlay);
            flash.external.ExternalInterface.addCallback("setVolume",foe._setVolume);
            //foe._playURL("called from self");
            foe.start_request();
        } else {
            trace("You need a newer Flash Player.");
            trace("Your version: " + flash.system.Capabilities.version);
            trace("The minimum required version: 10.0.0.525");
            flash.external.ExternalInterface.call("onOggState","error=need_flash_10.0.0.525_or_better");
        }
    }
}
