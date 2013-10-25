$(document).ready () ->
  # Pages
  # ================
  pages =
    login: document.querySelector '#page-login'
    caller: document.querySelector '#page-caller'

  # Globals
  # =================
  window.pubnub = null
  uuid = null
  currentCall = null
  myStream = null

  # Login
  # ================
  document.querySelector('#login').addEventListener 'click', (event) ->
    uuid = document.querySelector('#userid').value
    login uuid

  login = (name) ->
    uuid = name

    window.pubnub = PUBNUB.init
      publish_key: 'pub-c-7070d569-77ab-48d3-97ca-c0c3f7ab6403'
      subscribe_key: 'sub-c-49a2a468-ced1-11e2-a5be-02ee2ddab7fe'
      uuid: name

    pubnub.onNewConnection (uuid) ->
      unless not myStream
        publishStream uuid

    pages.login.className = pages.login.className.replace 'active', ''
    pages.caller.className += ' active'

    $(document).trigger 'pubnub:ready'

  # User List
  # ==================
  userTemplate = _.template $("#user-item-template").text()
  userList = $("#user-list")
  $(document).on 'pubnub:ready', (event) ->
    pubnub.subscribe
      channel: 'phonebook'
      callback: (message) ->
        # Do nothing
      presence: (data) ->
        # {
        #   action: "join"/"leave"
        #   timestamp: 12345
        #   uuid: "Dan"
        #   occupancy: 2
        # }
        if data.action is "join" and data.uuid isnt uuid
          newItem = userTemplate
            name: data.uuid
          userList.append newItem
        else if data.action is "leave" and data.uuid isnt uuid
          item = userList.find "li[data-user=\"#{data.uuid}\"]"
          item.remove()

  # Answering
  # =================
  caller = ''
  modal = $ '#answer-modal'
  modal.modal({ show: false })

  publishStream = (uuid) ->
    pubnub.publish
      user: uuid
      stream: myStream

    pubnub.subscribe
      user: uuid
      stream: (bad, event) ->
        document.querySelector('#call-video').src = URL.createObjectURL(event.stream)
      disconnect: (uuid, pc) ->
        document.querySelector('#call-video').src = ''

  answer = (otherUuid) ->
    currentCall = otherUuid
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
          currentCall = data.callee
          publishStream data.callee

  onCalling = (caller) ->
    modal.find('.caller').text "#{caller} is calling..."
    modal.modal 'show'

  modal.find('.btn-primary').on 'click', (event) ->
    answer caller
    modal.modal 'hide'

  # Calling
  # =================
  $('#user-list').on 'click', 'a[data-user]', (event) ->
    otherUuid = $(event.target).data 'user'
    currentCall = otherUuid

    pubnub.publish
      channel: 'call'
      message:
        caller: uuid
        callee: otherUuid

  # Hanging Up
  # ================
  $('#hang-up').on 'click', (event) ->
    pubnub.peerConnection currentCall, (peerConnection) ->
      peerConnection.close()

  gotStream = (stream) ->
    document.querySelector('#self-call-video').src = URL.createObjectURL(stream)
    #document.querySelector('#self-call-video').play()
    myStream = stream

  navigator.webkitGetUserMedia({audio: false, video: true}, gotStream)

  # Debug
  pages.caller.className += ' active'
  login("Guest" + Math.floor(Math.random() * 100))
  #pages.login.className += ' active'
