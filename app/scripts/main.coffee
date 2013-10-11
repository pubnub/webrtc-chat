pubnub = null
uuid = null
myStream = null

document.querySelector('#connect').addEventListener 'click', (event) ->
  uuid = document.querySelector('#userid').value

  pubnub = PUBNUB.init
    publish_key: 'pub-c-7070d569-77ab-48d3-97ca-c0c3f7ab6403'
    subscribe_key: 'sub-c-49a2a468-ced1-11e2-a5be-02ee2ddab7fe'
    uuid: uuid

  pubnub.onNewConnection (uuid) ->
    unless not myStream
      pubnub.publish
        user: uuid,
        stream: myStream

      pubnub.subscribe
        user: uuid
        stream: (bad, event) ->
          console.log "Got stream:", event
          document.querySelector('#call-video').src = URL.createObjectURL(event.stream)
          #document.querySelector('#call-video').play()

document.querySelector('#call').addEventListener 'click', (event) ->
  otherUuid = document.querySelector('#other-userid').value

  pubnub.publish
    user: otherUuid
    stream: myStream

  pubnub.subscribe
    user: otherUuid
    stream: (bad, event) ->
      console.log "Got stream:", event
      document.querySelector('#call-video').src = URL.createObjectURL(event.stream)
      #document.querySelector('#call-video').play()

gotStream = (stream) ->
  document.querySelector('#self-call-video').src = URL.createObjectURL(stream)
  #document.querySelector('#self-call-video').play()
  myStream = stream

navigator.webkitGetUserMedia({audio: false, video: true}, gotStream)