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
    login uuid

  login = (name) ->
    uuid = name

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
        login "#{result.id}-#{result.displayName}"
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
          currentCall = data.callee
          publishStream data.callee
          $(document).trigger "call:start", data.callee

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

  navigator.webkitGetUserMedia({audio: false, video: true}, gotStream)

  # Debug
  # pages.caller.className += ' active'
  # login("Guest" + Math.floor(Math.random() * 100))

  pages.login.className += ' active'
