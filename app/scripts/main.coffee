class GooglePlusClient
  constructor: (@token) ->
    @baseUrl = 'https://www.googleapis.com/plus/v1'

  getCurrentUser: (callback) ->
    req =
      url: @baseUrl + '/people/me'
      data:
        access_token: @token
        v: 3.0
        alt: 'json'
        'max-results': 10000
    $.ajax(req).done callback

  getContacts: (callback) ->
    req =
      url: @baseUrl + '/people/me/people/visible'
      data:
        access_token: @token
        v: 3.0
        alt: 'json'
        'max-results': 10000
    $.ajax(req).done callback

navigator.getUserMedia = navigator.getUserMedia or
                        navigator.webkitGetUserMedia or
                        navigator.mozGetUserMedia

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
  plusClient = null

  # Login
  # ================
  document.querySelector('#login').addEventListener 'click', (event) ->
    uuid = document.querySelector('#userid').value
    login "guest-#{uuid}"

  login = (name) ->
    uuid = name

    if plusClient?
      # Get the current list of contacts
      plusClient.getContacts (result) ->
        # result.items

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

  window.signinCallback = (authResult) ->
    if authResult['access_token']
      # Update the app to reflect a signed in user
      # Hide the sign-in button
      $('#signinButton').hide()

      # Create the google plus client
      plusClient = new GooglePlusClient authResult['access_token']

      # Get the user ID from google plus
      plusClient.getCurrentUser (result) ->
        # displayName
        # gender
        # id
        # image
        name = result.displayName.split(' ')
        name = name[0] + ' ' + name[1].charAt(0) + '.'
        login "#{result.id}-#{name}"
    else if authResult['error']
      # Update to reflect signed out user
      # Possible Values:
      # "user_signed_out" - User is signed out
      # "access_denied" - User denied access to your app
      # "immediate_failed" - Could not automatically log in to the user
      console.log "Sign-in state: #{authResult['error']}"

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
            name: data.uuid.split('-')[1]
            id: data.uuid
          userList.append newItem
        else if data.action is "leave" and data.uuid isnt uuid
          item = userList.find "li[data-user=\"#{data.uuid}\"]"
          item.remove()

  # Answering
  # =================
  caller = ''
  modalAnswer = $ '#answer-modal'
  modalAnswer.modal({ show: false })

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
        $(document).trigger "call:end"
      connect: (uuid, pc) ->
        # Do nothing

  answer = (otherUuid) ->
    if currentCall? and currentCall isnt otherUuid
      hangUp()

    currentCall = otherUuid
    publishStream otherUuid

    $(document).trigger "call:start", otherUuid

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
          if data.callee isnt currentCall
            hangUp()

          currentCall = data.callee
          publishStream data.callee
          $(document).trigger "call:start", data.callee

  onCalling = (caller) ->
    caller = caller.split('-')[1]
    modalAnswer.find('.caller').text "#{caller} is calling..."
    modalAnswer.modal 'show'

  modalAnswer.find('.btn-primary').on 'click', (event) ->
    answer caller
    modalAnswer.modal 'hide'

  # Calling
  # =================
  modalCalling = $ '#calling-modal'
  modalCalling.modal({ show: false })
  $('#user-list').on 'click', 'a[data-user]', (event) ->
    otherUuid = $(event.target).data 'user'
    currentCall = otherUuid

    name = otherUuid.split('-')[1]
    modalCalling.find('.calling').text "Calling #{name}..."
    modalCalling.modal 'show'

    pubnub.publish
      channel: 'call'
      message:
        caller: uuid
        callee: otherUuid

  $(document).on 'call:start', () ->
    modalCalling.modal 'hide'

  # Text Chat
  # ================
  messageBox = $ '#chat-receive-message'
  messageInput = $ '#chat-message'
  messageBox.text ''
  messageControls = $ '#chat-area'
  messageControls.hide()

  getCombinedChannel = () ->
    if currentCall > uuid
      "#{currentCall}-#{uuid}"
    else
      "#{uuid}-#{currentCall}"

  $(document).on "call:start", (event) =>
    messageControls.show()
    messageBox.text ''
    pubnub.subscribe
      channel: getCombinedChannel()
      callback: (message) ->
        messageBox.append "<br />#{message}"
        messageBox.scrollTop messageBox[0].scrollHeight

  $(document).on "call:end", (event) =>
    messageControls.hide()
    pubnub.unsubscribe
      channel: getCombinedChannel()

  messageInput.on 'keydown', (event) =>
    if event.keyCode is 13 and currentCall?
      pubnub.publish
        channel: getCombinedChannel()
        message: uuid.split('-')[1] + ": " + messageInput.val()
      messageInput.val ''

  # Hanging Up
  # ================
  $('#hang-up').on 'click', (event) ->
    hangUp()

  hangUp = () ->
    pubnub.closeConnection currentCall, () ->
      $(document).trigger "call:end"

  # Call Status
  # ================
  videoControls = $ '#video-controls'
  timeEl = videoControls.find '#time'
  time = 0
  timeInterval = null
  videoControls.hide()

  increment = () ->
    time += 1
    minutes = Math.floor(time / 60)
    seconds = time % 60
    if minutes.toString().length is 1 then minutes = "0#{minutes}"
    if seconds.toString().length is 1 then seconds = "0#{seconds}"
    timeEl.text "#{minutes}:#{seconds}"

  $(document).on "call:start", (event) =>
    videoControls.show()
    time = 0
    timeEl.text "00:00"
    timeInterval = setInterval increment, 1000

  $(document).on "call:end", (event) =>
    videoControls.hide()
    clearInterval timeInterval

  gotStream = (stream) ->
    document.querySelector('#self-call-video').src = URL.createObjectURL(stream)
    #document.querySelector('#self-call-video').play()
    myStream = stream

  navigator.getUserMedia {audio: true, video: true}, gotStream, (error) ->
    console.log("Error getting user media: ", error)

  # Debug
  # pages.caller.className += ' active'
  # login("Guest" + Math.floor(Math.random() * 100))

  # pages.login.className += ' active'
