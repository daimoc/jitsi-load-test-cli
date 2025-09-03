#!/bin/bash

# Gst-Meet image used by the load tester
GST_IMAGE="daimoc/gst-meet"

# Function to display usage instructions
usage() {
    echo "Usage: $0 --room ROOM --domain DOMAIN --video-publishers NUM --audio-publishers NUM --subscribers NUM --duration DURATION --media FILE --video-codec VIDEO_CODEC --token TOKEN --time_between_agent WAIT_TIME --last-n LAST_N --room-numbers NUM --xmpp-domain DOMAIN --focus-jid JID --muc-domain DOMAIN"
    echo
    echo " Mandatory Options : "
    echo "  --room                Name of the room"
    echo "  --domain              Jitsi domain ( meet.jitsi) "
    echo " Other options:"
    echo "  --video-publishers    Number of video publishers"
    echo "  --audio-publishers    Number of audio publishers"
    echo "  --subscribers         Number of subscribers"
    echo "  --duration            Duration of the test in seconds"
    echo "  --time_between_agent  Wait time in seconds between 2 agent launch (default to 1 second)"
    echo "  --media               Name of the video file stored in media folder used for traffic generation"
    echo "  --video-codec         Video codec used by video sender agents. It must match your media file becaus we don't want codec transcription in a load testing tool (default to vp8)"
    echo "  --token               JWT token to run test on Jitsi-Meet with authentification enable"
    echo "  --last-n              Last-N value setting for subscribers to limit received video streams per subscribers (default to 25)"
    echo "  --room-numbers        Number of rooms created for the test. Each room is named $room_$index"
    echo "  --xmpp-domain         XMPP domain (default: meet.jitsi)"
    echo "  --focus-jid           Focus JID (default: focus.meet.jitsi)"
    echo "  --muc-domain          MUC domain (default: muc.meet.jitsi)"
    exit 1
}

run_agent(){
    NUMBER=$1
    TYPE=$2

    VIDEO_SENDER_PIPELINE="filesrc location=/media/$MEDIA ! queue max-size-time=200000 ! matroskademux name=demuxer  demuxer.video_0 ! queue max-size-time=10000 name=video demuxer.audio_0 ! queue max-size-time=10000 name=audio"
    AUDIO_SENDER_PIPELINE="filesrc location=/media/$MEDIA ! queue max-size-time=200000 ! matroskademux name=demuxer demuxer.audio_0 ! queue max-size-time=10000 name=audio"
    RECEIVER_PIPELINE="queue max-size-time=1000 name=audio ! fakeaudiosink queue max-size-time=1000 name=video ! fakevideosink"

    echo "Agent $TYPE"
    case "$TYPE" in
    "AUDIO")
        SENDER_PIPELINE=$AUDIO_SENDER_PIPELINE
        ;;
    "VIDEO")
        SENDER_PIPELINE=$VIDEO_SENDER_PIPELINE 
        ;;
    "SUBSCRIBER")
        unset SENDER_PIPELINE
        ;;
    *)
        echo "Invalid option: Agent $TYPE"
        exit 0
        ;;
    esac

    if [[ $ROOM_NUMBERS -eq 0 ]]; then  
        for i in `seq 1 $NUMBER`
        do
            NICK=$TYPE"_$i"
            sleep $WAIT_TIME

            if [ -z ${SENDER_PIPELINE+x} ]; then
                docker run -d \
                    --net=host \
                    --log-driver=none \
                    $GST_IMAGE \
                    --video-codec=$VIDEO_CODEC \
                    --nick $NICK \
                    --last-n $LAST_N \
                    --room-name $ROOM \
                    --web-socket-url wss://$DOMAIN/xmpp-websocket?room=$ROOM\&token=$TOKEN \
                    --xmpp-domain=$XMPP_DOMAIN --focus-jid=$FOCUS_JID --muc-domain=$MUC_DOMAIN \
                    --verbose=0 \
                    --recv-pipeline-participant-template="$RECEIVER_PIPELINE" \
                    > /dev/null 2>&1
            else 
                docker run -d \
                    --net=host \
                    --log-driver=none \
                    --mount type=bind,source="$(pwd)"/media,target=/media,ro \
                    $GST_IMAGE \
                    --video-codec=$VIDEO_CODEC \
                    --nick $NICK \
                    --last-n $LAST_N \
                    --room-name $ROOM \
                    --web-socket-url wss://$DOMAIN/xmpp-websocket?room=$ROOM\&token=$TOKEN \
                    --xmpp-domain=$XMPP_DOMAIN --focus-jid=$FOCUS_JID --muc-domain=$MUC_DOMAIN \
                    --verbose=0 \
                    --send-pipeline="$SENDER_PIPELINE" \
                    --recv-pipeline-participant-template="$RECEIVER_PIPELINE" \
                    > /dev/null 2>&1
            fi
            echo "Start agent" $NICK $ROOM
        done
    else
        for j in `seq 1 $ROOM_NUMBERS`
        do
            ROOM_NAME=$ROOM"_"$j
            for i in `seq 1 $NUMBER`
            do
                NICK=$TYPE"_$i"
                sleep $WAIT_TIME

                if [ -z ${SENDER_PIPELINE+x} ]; then
                    docker run -d \
                        --net=host \
                        --log-driver=none \
                        $GST_IMAGE \
                        --video-codec=$VIDEO_CODEC \
                        --nick $NICK \
                        --last-n $LAST_N \
                        --room-name $ROOM_NAME \
                        --web-socket-url wss://$DOMAIN/xmpp-websocket?room=$ROOM\&token=$TOKEN \
                        --xmpp-domain=$XMPP_DOMAIN --focus-jid=$FOCUS_JID --muc-domain=$MUC_DOMAIN \
                        --verbose=0 \
                        --recv-pipeline-participant-template="$RECEIVER_PIPELINE" \
                        > /dev/null 2>&1
                else
                    docker run -d \
                        --net=host \
                        --log-driver=none \
                        --mount type=bind,source="$(pwd)"/media,target=/media,ro \
                        $GST_IMAGE \
                        --video-codec=$VIDEO_CODEC \
                        --nick $NICK \
                        --last-n $LAST_N \
                        --room-name $ROOM_NAME \
                        --web-socket-url wss://$DOMAIN/xmpp-websocket?room=$ROOM\&token=$TOKEN \
                        --xmpp-domain=$XMPP_DOMAIN --focus-jid=$FOCUS_JID --muc-domain=$MUC_DOMAIN \
                        --verbose=0 \
                        --send-pipeline="$SENDER_PIPELINE" \
                        --recv-pipeline-participant-template="$RECEIVER_PIPELINE" \
                        > /dev/null 2>&1
                fi
                echo "Start agent" $NICK $ROOM_NAME
            done
        done
    fi
}

stop_agents(){
    echo "Stop all gst-meet containers"
    docker container kill `docker ps |grep "gst-meet"|awk '{print $1}'`
    docker container rm `docker container ls -a |grep "gst-meet"|awk '{print $1}'`
}

cleanup() {
    echo "Jitsi Load test interrupted. Performing cleanup..."
    stop_agents;
    exit 1
}

trap cleanup SIGINT

ROOM=""
DOMAIN=""
VIDEO_PUBLISHERS=0
AUDIO_PUBLISHERS=0
SUBSCRIBERS=0
DURATION=0
MEDIA="bbb.webm"
TOKEN=""
WAIT_TIME=1
LAST_N=25
VIDEO_CODEC="vp8"
ROOM_NUMBERS=0
XMPP_DOMAIN="meet.jitsi"
FOCUS_JID="focus.meet.jitsi"
MUC_DOMAIN="muc.meet.jitsi"

while [ "$1" != "" ]; do
    case $1 in
        --room )              shift; ROOM=$1 ;;
        --domain )            shift; DOMAIN=$1 ;;
        --video-publishers )  shift; VIDEO_PUBLISHERS=$1 ;;
        --audio-publishers )  shift; AUDIO_PUBLISHERS=$1 ;;
        --subscribers )       shift; SUBSCRIBERS=$1 ;;
        --duration )          shift; DURATION=$1 ;;
        --time_between_agent) shift; WAIT_TIME=$1 ;;
        --media )             shift; MEDIA=$1 ;;
        --video-codec )       shift; VIDEO_CODEC=$1 ;;
        --token )             shift; TOKEN=$1 ;;
        --last-n )            shift; LAST_N=$1 ;;
        --room-numbers )      shift; ROOM_NUMBERS=$1 ;;
        --xmpp-domain )       shift; XMPP_DOMAIN=$1 ;;
        --focus-jid )         shift; FOCUS_JID=$1 ;;
        --muc-domain )        shift; MUC_DOMAIN=$1 ;;
        * )                   usage; exit 1
    esac
    shift
done

if [ -z "$ROOM" ] || [ -z "$DOMAIN" ] || [ -z "$DURATION" ]; then
    usage
fi

echo "Starting load test with the following parameters:"
echo "Room: $ROOM"
echo "Domain: $DOMAIN"
echo "Video Publishers: $VIDEO_PUBLISHERS"
echo "Audio Publishers: $AUDIO_PUBLISHERS"
echo "Subscribers: $SUBSCRIBERS"
echo "Duration: $DURATION seconds"
echo "Media File: $MEDIA"
echo "JWT Token: $TOKEN"
echo "Last-N : $LAST_N"
echo "Video Codec: $VIDEO_CODEC"
echo "Room Numbers: $ROOM_NUMBERS"
echo "XMPP Domain: $XMPP_DOMAIN"
echo "Focus JID: $FOCUS_JID"
echo "MUC Domain: $MUC_DOMAIN"

echo "Running Jitsi-Meet load test using media file $MEDIA..."

run_agent $VIDEO_PUBLISHERS VIDEO;
run_agent $AUDIO_PUBLISHERS AUDIO;
run_agent $SUBSCRIBERS SUBSCRIBER;

sleep $DURATION
stop_agents;

echo "Load test completed."
