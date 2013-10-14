$(document).ready () ->
  # Pages
  # ================
  pages =
    login: document.querySelector '#page-login'
    caller: document.querySelector '#page-caller'

  for page of pages
    pages[page].className += ' page'
  pages.login.className += ' active'

  # Globals
  # =================
  window.pubnub = null
  uuid = null
  myStream = null

  # Login
  # ================
  document.querySelector('#login').addEventListener 'click', (event) ->
    uuid = document.querySelector('#userid').value

    window.pubnub = PUBNUB.init
      publish_key: 'pub-c-7070d569-77ab-48d3-97ca-c0c3f7ab6403'
      subscribe_key: 'sub-c-49a2a468-ced1-11e2-a5be-02ee2ddab7fe'
      uuid: uuid

    pubnub.onNewConnection (uuid) ->
      unless not myStream
        publishStream uuid

    pages.login.className = pages.login.className.replace 'active', ''
    pages.caller.className += ' active'

    $(document).trigger 'pubnub:ready'

  # Answering
  # =================
  caller = ''
  modal = $ '#answer-modal'
  modal.modal({ show: false })

  publishStream = (uuid) ->
    console.log "Publishing Stream!!!", uuid
    pubnub.publish
      user: uuid
      stream: myStream

    pubnub.subscribe
      user: uuid
      stream: (bad, event) ->
        console.log "Got stream:", event
        document.querySelector('#call-video').src = URL.createObjectURL(event.stream)

  answer = (otherUuid) ->
    publishStream otherUuid

    pubnub.publish
      channel: 'answer'
      message:
        caller: caller
        callee: uuid

  $(document).on 'pubnub:ready', (event) =>
    pubnub.subscribe
      channel: 'call'
      callback: (data) ->
        if data.callee is uuid
          caller = data.caller
          onCalling data.caller

    pubnub.subscribe
      channel: 'answer'
      callback: (data) ->
        if data.caller is uuid
          publishStream data.callee

  onCalling = (caller) ->
    modal.find('.caller').text "#{caller} is calling..."
    modal.modal 'show'

  modal.find('.btn-primary').on 'click', (event) ->
    answer caller
    modal.modal 'hide'

  # Calling
  # =================
  document.querySelector('#call').addEventListener 'click', (event) ->
    otherUuid = document.querySelector('#other-userid').value

    pubnub.publish
      channel: 'call'
      message:
        caller: uuid
        callee: otherUuid

  gotStream = (stream) ->
    document.querySelector('#self-call-video').src = URL.createObjectURL(stream)
    #document.querySelector('#self-call-video').play()
    myStream = stream

  navigator.webkitGetUserMedia({audio: false, video: true}, gotStream)
