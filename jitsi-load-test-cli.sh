#!/bin/bash

# Gst-Meet image used by the load tester
GST_IMAGE="daimoc/gst-meet"

# Function to display usage instructions
usage() {
    echo "Usage: $0 --room ROOM --instance INSTANCE --video-publishers NUM --audio-publishers NUM --subscribers NUM --duration DURATION --media FILE --video-codec VIDEO_CODEC --token TOKEN --time_between_agent WAIT_TIME --last-n LAST_N"
    echo
    echo " Mandatory Options : "
    echo "  --room                Name of the room"
    echo "  --instance            Instance identifier"
    echo " Other options:"
    echo "  --video-publishers    Number of video publishers"
    echo "  --audio-publishers    Number of audio publishers"
    echo "  --subscribers         Number of subscribers"
    echo "  --duration            Duration of the test in seconds"
    echo "  --time_between_agent  Wait time in seconds between 2 agent launch (default to 1)"
    echo "  --media               Name of the video file stored in media folder used for traffic generation"
    echo "  --video-codec         Video codec used by video sender agents. It must match your media file becaus we don't want codec transcription in a load testing tool (default to vp8)"
    echo "  --token               JWT token to run test on Jitsi-Meet with authentification enable"
    echo "  --last-n              Last-N value setting for subscribers to limit received video streams per subscribers (default to 25)"
  
    exit 1
}


run_agent(){
    NUMBER=$1
    TYPE=$2

    # Main variables for agent configuration 
    VIDEO_SENDER_PIPELINE="filesrc location=/media/$MEDIA ! queue max-size-time=200000 ! matroskademux name=demuxer  demuxer.video_0 ! queue max-size-time=10000 name=video demuxer.audio_0 ! queue max-size-time=10000 name=audio"
    AUDIO_SENDER_PIPELINE="filesrc location=/media/$MEDIA ! queue max-size-time=200000 ! matroskademux name=demuxer demuxer.audio_0 ! queue max-size-time=10000 name=audio"
    RECEIVER_PIPELINE="queue max-size-time=1000 name=audio ! fakeaudiosink queue max-size-time=1000 name=video ! fakevideosink"

    echo "Agent $TYPE"
    case "$TYPE" in
    "AUDIO")
        SENDER_PIPELINE=$AUDIO_SENDER_PIPELINE
        LAST_N=0
        ;;
    "VIDEO")
        SENDER_PIPELINE=$VIDEO_SENDER_PIPELINE 
        LAST_N=0
        ;;
    "SUBSCRIBER")
        ;;
    *)
        echo "Invalid option: Agent $TYPE"
        exit 0
        ;;
    esac

    for i in `seq 1 $NUMBER`
    do
        NICK=$TYPE"_$i"
        sleep $WAIT_TIME
        docker run \
        --mount type=bind,source="$(pwd)"/media,target=/media \
        $GST_IMAGE \
        --video-codec=$VIDEO_CODEC \
        --nick $NICK \
        --last-n $LAST_N \
        --room-name $ROOM \
        --web-socket-url wss://$INSTANCE/xmpp-websocket?room=$ROOM\&token=$TOKEN \
        --xmpp-domain=$INSTANCE \
        --verbose=0 \
        --send-pipeline="$SENDER_PIPELINE" \
        --recv-pipeline-participant-template="$RECEIVER_PIPELINE" \
        > /dev/null 2>&1 &

        echo "Start agent" $NICK
    done
}

stop_agents(){
    echo "Stop all gst-meet containers"
    docker container kill `docker ps |grep "gst-meet"|awk '{print $1}'`
    docker container rm `docker container ls -a |grep "gst-meet"|awk '{print $1}'`
}

# Function to handle cleanup on exit
cleanup() {
    echo "Jitsi Load test interrupted. Performing cleanup..."
    stop_agents;
    exit 1
}

# Trap SIGINT (Ctrl-C) and call the cleanup function
trap cleanup SIGINT

# Initialize variables
ROOM=""
INSTANCE=""
VIDEO_PUBLISHERS=0
AUDIO_PUBLISHERS=0
SUBSCRIBERS=0
DURATION=0
MEDIA="bbb.webm"
TOKEN=""
WAIT_TIME=1
LAST_N=25
VIDEO_CODEC="vp8"

# Parse command line arguments
while [ "$1" != "" ]; do
    case $1 in
        --room )              shift
                              ROOM=$1
                              ;;
        --instance )          shift
                              INSTANCE=$1
                              ;;
        --video-publishers )  shift
                              VIDEO_PUBLISHERS=$1
                              ;;
        --audio-publishers )  shift
                              AUDIO_PUBLISHERS=$1
                              ;;
        --subscribers )       shift
                              SUBSCRIBERS=$1
                              ;;
        --duration )          shift
                              DURATION=$1
                              ;;
        --time_between_agent) shift
                              WAIT_TIME=$1
                              ;;
        --media )             shift
                              MEDIA=$1
                              ;;
        --video-codec )       shift
                              VIDEO_CODEC=$1
                              ;;
        --token )             shift
                              TOKEN=$1
                              ;;
        --Last-n )            shift
                              LAST_N=$1
                              ;;
        * )                   usage
                              exit 1
    esac
    shift
done

# Validate required arguments
if [ -z "$ROOM" ] || [ -z "$INSTANCE" ] || [ -z "$DURATION" ]; then
    usage
fi

# Display the parameters for the load test
echo "Starting load test with the following parameters:"
echo "Room: $ROOM"
echo "Instance: $INSTANCE"
echo "Video Publishers: $VIDEO_PUBLISHERS"
echo "Audio Publishers: $AUDIO_PUBLISHERS"
echo "Subscribers: $SUBSCRIBERS"
echo "Duration: $DURATION seconds"
echo "Media File: $MEDIA"
echo "JWT Token: $TOKEN"
echo "Last-N : $LAST_N"
echo "Video Codec: $VIDEO_CODEC"

echo "Running Jitsi-Meet load test using media file $MEDIA..."

run_agent $VIDEO_PUBLISHERS VIDEO;

run_agent $AUDIO_PUBLISHERS AUDIO;

run_agent $SUBSCRIBERS SUBSCRIBER;


# Example: Sleep for the duration to simulate a test
sleep $DURATION
stop_agents;

echo "Load test completed."