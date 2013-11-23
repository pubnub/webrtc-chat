(function (window, PUBNUB) {
  //"use strict";

  // Remove vendor prefixes
  var IS_CHROME = !!window.webkitRTCPeerConnection,
      RTCPeerConnection,
      RTCIceCandidate,
      RTCSessionDescription;

  if (IS_CHROME) {
    RTCPeerConnection = webkitRTCPeerConnection;
    RTCIceCandidate = window.RTCIceCandidate;
    RTCSessionDescription = window.RTCSessionDescription;
  } else {
    RTCPeerConnection = mozRTCPeerConnection;
    RTCIceCandidate = mozRTCIceCandidate;
    RTCSessionDescription = mozRTCSessionDescription;
  }

  // Global error handling function
  function error() {
    console['error'].apply(console, arguments);
  }

  // Global info logging
  var isDebug = true;
  function debug() {
    if (isDebug === true) {
      console['log'].apply(console, arguments);
    }
  }

  // Grabs an attribute from a node.
  function attr(node, attribute, value) {
    if (value) {
      node.setAttribute(attribute, value);
    }
    else {
      return node && node.getAttribute && node.getAttribute(attribute);
    }
  }

  // Extend function for adding to existing objects
  function extend(obj, other) {
    for (var key in other) {
      obj[key] = other[key];
    }
    return obj;
  }

  // Putting UUID function here to work around non-exposed ID issues.
  function generateUUID() {
    var u = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,
    function (c) {
      var r = Math.random() * 16 | 0, v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
    return u;
  }

  // Hack for Chrome to allow adequate throughput over DataChannel
  function transformOutgoingSdp(sdp) {
    var splitted = sdp.split("b=AS:30");
    if (splitted.length === 1) {
      return sdp;
    }
    var newSDP = splitted[0] + "b=AS:1638400" + splitted[1];
    return newSDP;
  }

  function extendAPI(PUBNUB, uuid) {
    // Store out API so we can extend it on all instances.
    var API = {},
        PREFIX = "pn_",               // Prefix for subscribe channels
        PEER_CONNECTIONS = {},        // Connection storage by uuid
        RTC_CONFIGURATION = {
          iceServers: [
            { 'url': (IS_CHROME ? 'stun:stun.l.google.com:19302' : 'stun:23.21.150.121') }
          ]
        },     // Global config for RTC's
        PC_OPTIONS = (IS_CHROME ? {
          optional: [
          { RtpDataChannels: true }
          ]
        } : {}),
        UUID = uuid,                  // The current user's UUID
        PUBLISH_QUEUE = {},           // The queue of messages to send by UUID
        CONNECTED = false,            // If we have connected to the personal channel yet
        CONNECTION_QUEUE = [],        // Any createP2PConnection calls we get before we connect
        PUBLISH_TYPE = {              // Publish type enum
          STREAM: 1,
          MESSAGE: 2
        },
        ON_NEW_CONNECTION = [];

    // Expose PUBNUB UUID (Need to fix this in core)
    PUBNUB['UUID'] = uuid;

    // SignalingChannel
    // The signaling channel handles sending data to and from a specific user channel.
    function SignalingChannel(pubnub, selfUuid, otherUuid) {
      var queue = [];
      this.peerReady = false;
      this.selfUuid = selfUuid;
      this.otherUuid = otherUuid;

      // The send function is here so we do not count a reference to PubNub preventing its destruction.
      this.send = function (message, force) {
        var strMsg = message;
        message.uuid = selfUuid;
        force = true;

        if (this.peerReady === true || force === true) {
          if (message.sdp) {
          }
          debug("Sending to: ", PREFIX + otherUuid, " message ", message);
          pubnub.publish({
            channel: PREFIX + otherUuid,
            message: message
          });
        } else {
          queue.push(strMsg);
        }
      };
      this.initiate = function () {
        this.send({ initiation: true }, true);
      };
      this.peerIsReady = function () {
        this.peerReady = true;
        queue.unshift({ negotiationReady: true });
        queue.forEach(function (msg) {
          this.send(msg);
        }.bind(this));
        queue = [];
      };
    }

    function personalChannelCallback(message) {
      debug("Personal channel callback: ", message);

      if (message.uuid != null) {
        if (message.uuid === UUID) {
          return;
        }

        var connected = PEER_CONNECTIONS[message.uuid] != null;

        // Setup the connection if we do not have one already.
        if (connected === false) {
          PUBNUB.createP2PConnection(message.uuid, false, function (uuid) {
            for(var i = 0; i < ON_NEW_CONNECTION.length; i++) {
              var callback = ON_NEW_CONNECTION[i];
              callback(uuid);
            }
          });
        }

        var connection = PEER_CONNECTIONS[message.uuid];

        if (!connection.signalingChannel.peerReady) {
          connection.signalingChannel.peerIsReady();
        }

        if (message.sdp != null) {
          debug("Remote Session Description:", message.sdp);
          connection.connection.setRemoteDescription(new RTCSessionDescription(message.sdp), function () {
            // Add ice candidates we might have gotten early.
            var candidates = connection.candidates;
            debug("Adding ice candidates", candidates, connection);
            for (var i = 0; i < candidates.length; i++) {
              debug("Remote ICE Candidate (backfill):", candidates[i]);
              connection.connection.addIceCandidate(new RTCIceCandidate(candidates[i]));
              connection.connection.candidates = [];
            }

            // If we did not create the offer then create the answer.
            if (connection.connection.signalingState === 'have-remote-offer') {
              debug("Creating answer...", message.uuid);
              connection.connection.createAnswer(function (description) {
                PUBNUB.gotDescription(description, connection);
              }, function (err) {
                // Connection failed, so delete it from the table
                delete PEER_CONNECTIONS[message.uuid];
                error("Error creating answer: ", err);
              });
            }
          }, function (err) {
            // Maybe notify the peer that we can't communicate
            error("Error setting remote description: ", err);
          });
        } else if (message.initiation === true) {
          //PUBNUB.createP2PConnection(message.uuid, true);
        } else if (message.candidate) {
          if (connection.connection.remoteDescription != null) {// && connection.connection.iceConnectionState !== "connected") {
            debug("Remote ICE Candidate:", message.candidate);
            connection.connection.addIceCandidate(new RTCIceCandidate(message.candidate));
          }
          else {
            // This is to prevent adding ice candidates before the remote description
            connection.candidates.push(message.candidate);
          }
        }
      }
    }

    // Subscribe to our own personal channel to listen for data.
    PUBNUB.subscribe({
      channel: PREFIX + uuid,
      //restore: false,
      //timetoken: backfillTime * Math.pow(10, 7),
      connect: function () {
        CONNECTED = true;

        debug("Connected to channel: ", PREFIX + uuid);

        for (var i = 0; i < CONNECTION_QUEUE.length; i++) {
          var args = CONNECTION_QUEUE[i];

          if (args.length > 1) {
            // We need to send a description because we are the "host"
            args[1].signalingChannel.initiate();
            debug("Connection Queue Description", args);
            PUBNUB.gotDescription.apply(PUBNUB, args);
          } else if (args.length === 1) {
            // We are not the "host" so we send initiation
            args[0].signalingChannel.initiate();
          }
        }

        CONNECTION_QUEUE = [];
      },
      callback: personalChannelCallback
    });

    // PUBNUB._gotDescription
    // This is the handler for when we get a SDP description from the WebRTC API.
    API['gotDescription'] = function (description, connection) {
      /***
       * CHROME HACK TO GET AROUND BANDWIDTH LIMITATION ISSUES
       ***/
      if (IS_CHROME) {
        //description.sdp = transformOutgoingSdp(description.sdp);
      }

      if (connection.connection.signalingState !== 'have-local-offer') {
        debug("Local Session Description", description.sdp);
        connection.connection.setLocalDescription(description, function () {

        }, function (error) {
          debug("Error setting local description: ", error);
        });
      }

      if (CONNECTED === false) {
        debug("Not connected");
        CONNECTION_QUEUE.push([description, connection]);
      } else {
        connection.signalingChannel.send({
          "sdp": description
        });
      }
    };

    API['onNewConnection'] = function (callback) {
      ON_NEW_CONNECTION.push(callback);
    };

    // PUBNUB.createP2PConnection
    // Signals and creates a P2P connection between two users.
    API['createP2PConnection'] = function (uuid, offer, callback) {
      if (PEER_CONNECTIONS[uuid] == null) {
        var pc = new RTCPeerConnection(RTC_CONFIGURATION, PC_OPTIONS),
            signalingChannel = new SignalingChannel(this, UUID, uuid),
            self = this;

        var onDataChannelCreated = function (event) {
          PEER_CONNECTIONS[uuid].dataChannel = event.channel;

          PEER_CONNECTIONS[uuid].dataChannel.onmessage = function (event) {
            var data = event.data;

            // Try to automagically parse JSON data
            try {
              data = JSON.parse(event.data);
            } catch (exception) {
              // Do nothing
            }

            if (PEER_CONNECTIONS[uuid].callback) {
              PEER_CONNECTIONS[uuid].callback(data, event);
            } else {
              // Store it in the history so the user can still get to it
              PEER_CONNECTIONS[uuid].history.push(data);
            }
          };

          debug("Add handler for streams.");
          PEER_CONNECTIONS[uuid].connection.onaddstream = function (event) {
            debug("On Stream Add", event, PEER_CONNECTIONS[uuid].stream);
            if (PEER_CONNECTIONS[uuid].stream) {
              PEER_CONNECTIONS[uuid].stream(event.data, event);
            } else {
              // Store it in the history so the user can still get to it
              PEER_CONNECTIONS[uuid].history.push(event.data);
            }
          };

          PEER_CONNECTIONS[uuid].dataChannel.onopen = function () {
            PEER_CONNECTIONS[uuid].connected = true;
            self._peerPublish(uuid);
          };
        };
        pc.ondatachannel = onDataChannelCreated;

        pc.onicecandidate = function (event) {
          // TODO: Figure out why we get a null candidate
          if (event.candidate != null) {
            signalingChannel.send({ "candidate": event.candidate });
          }
        };

        pc.onsignalingstatechange = function () {
          debug("Signaling state change: ", pc.signalingState);

          if (pc.signalingState === "closed") {
            // Not sure why this does not always get called
          }
        };

        pc.oniceconnectionstatechange = function () {
          debug("Connection state change: ", pc.iceConnectionState);
          if (pc.iceConnectionState === "connected") {
            // Handle event for connect state
            if (PEER_CONNECTIONS[uuid].events.connect) {
              PEER_CONNECTIONS[uuid].events.connect(uuid, pc);
            }
          } else if (pc.iceConnectionState === "disconnected") {
            // Handle closed event for connection
            if (PEER_CONNECTIONS[uuid].events.disconnect) {
              PEER_CONNECTIONS[uuid].events.disconnect(uuid, pc);
              closeConnection(uuid);
            }
          }
        };

        PUBLISH_QUEUE[uuid] = [];

        PEER_CONNECTIONS[uuid] = {
          connection: pc,
          candidates: [],
          connected: false,
          createdOffer: offer !== false,
          history: [],
          signalingChannel: signalingChannel,
          events: {}
        };

        if (callback) {
          callback(uuid);
        }

        // Compare UUIDs to guarantee we determine the 'leader' for negotiating the connection
        if (UUID > uuid) {
          var dc = pc.createDataChannel("pubnub", (IS_CHROME ? { reliable: false } : {}));
          onDataChannelCreated({
            channel: dc
          });

          debug("Creating offer...", uuid);
          pc.createOffer(function (description) {
            self.gotDescription(description, PEER_CONNECTIONS[uuid]);
          }, function (err) {
            // Connection failed, so delete it from the table
            delete PEER_CONNECTIONS[uuid];
            error(err);
          }, {mandatory:{OfferToReceiveAudio:true,OfferToReceiveVideo:true}});
        } else {
          if (CONNECTED === false) {
            CONNECTION_QUEUE.push([PEER_CONNECTIONS[uuid]]);
          } else {
            signalingChannel.initiate();
          }
        }
      } else {
        debug("Trying to connect to already connected user: " + uuid);
      }
    };

    // Helper function for sending messages with different types.
    function handleMessage(connection, message) {
      debug("Handling message", connection, message);
      if (message.type === PUBLISH_TYPE.STREAM) {
        debug("Adding stream", message.stream);
        connection.connection.addStream(message.stream);
      } else if (message.type === PUBLISH_TYPE.MESSAGE) {
        // Convert to JSON automagically
        if (typeof message.message === "object") {
          //message.message = JSON.stringify(message.message);
        }

        connection.dataChannel.send(message.message);
      } else {
        error("Unrecognized RTC message type: " + message.type);
      }
    }

    // PUBNUB._peerPublish
    // Handles requesting a peer connection and emptying the queue when connected.
    API['_peerPublish'] = function (uuid) {
      if (PUBLISH_QUEUE[uuid] && PUBLISH_QUEUE[uuid].length > 0) {
        debug("Connected", PEER_CONNECTIONS[uuid].connected, uuid);
        if (PEER_CONNECTIONS[uuid].connected === true) {
          handleMessage(PEER_CONNECTIONS[uuid], PUBLISH_QUEUE[uuid].shift());
          this._peerPublish(uuid);
        } else {
          // Not connected yet so just sit tight!
        }
      } else {
        // Nothing to publish
        return;
      }
    };

    // PUBNUB.publish overload
    API['publish'] = (function (_super) {
      return function (options) {
        var exists = PEER_CONNECTIONS[options.user] != null;

        if (options == null) {
          error("You must send an object when using PUBNUB.publish!");
        }

        if (options.user != null) {
          // Setup the connection if it does not exist
          if (PEER_CONNECTIONS[options.user] == null) {
            PUBNUB.createP2PConnection(options.user, null, function () {
              if (options.stream != null) {
                debug("Publishing stream to user", options.stream, options.user);
                PEER_CONNECTIONS[options.user].connection.addStream(options.stream);
              }
            });
          }

          if (options.stream != null) {
            if (exists === true) {
              debug("Publishing stream to user", options.stream, options.user);
              PEER_CONNECTIONS[options.user].connection.addStream(options.stream);
            }
            // PUBLISH_QUEUE[options.user].push({
            //   type: PUBLISH_TYPE.STREAM,
            //   stream: options.stream
            // });
            // handleMessage(PEER_CONNECTIONS[options.user], PUBLISH_QUEUE[options.user].shift());
          } else if (options.message != null) {
            PUBLISH_QUEUE[options.user].push({
              type: PUBLISH_TYPE.MESSAGE,
              message: options.message
            });
          } else {
            error("Stream or message key not found in argument object. One or the other must be provided for RTC publish calls!");
          }

          this._peerPublish(options.user);
        } else {
          _super.apply(this, arguments);
        }
      };
    })(PUBNUB['publish']);

    // PUBNUB.subscribe overload
    API['subscribe'] = (function (_super) {
      return function (options) {
        if (options == null) {
          error("You must send an object when using PUBNUB.subscribe!");
        }

        if (options.user != null) {
          // Setup the connection if it does not exist
          if (PEER_CONNECTIONS[options.user] == null) {
            PUBNUB.createP2PConnection(options.user);
          }

          var connection = PEER_CONNECTIONS[options.user];

          if (options.stream) {
            // Setup the stream added listener
            connection.stream = options.stream;
          }

          if (options.callback) {
            // Setup the data channel callback listener
            connection.callback = options.callback;
          }

          connection.events = options;

          // Replay the backfilled messages if they exist
          debug("Subscribing to user: ", options.user, connection.history);
          if (connection.history.length > 0) {
            for (var i = 0; i < connection.history.length; i++) {
              var message = connection.history[i];

              if (options.callback) {
                options.callback(message);
              }
            }
          }
        } else {
          return _super.apply(this, arguments);
        }
      };
    })(PUBNUB['subscribe']);

    // PUBNUB.unsubscribe overload
    API['unsubscribe'] = (function (_super) {
      return function (options) {
        if (options == null) {
          error("You must send an object when using PUBNUB.unsubscribe!");
        }

        if (options.user != null) {
          var connection = PEER_CONNECTIONS[options.user];

          if (connection != null) {
            if (connection.dataChannel != null) {
              connection.dataChannel.close();
            }
            connection.connection.close();
            PEER_CONNECTIONS[options.user] = null;
          }
        } else {
          return _super.apply(this, arguments);
        }
      };
    })(PUBNUB['unsubscribe']);

    // PUBNUB.history overload
    API['history'] = (function (_super) {
      return function (options) {
        if (options == null) {
          error("You must send an object when using PUBNUB.history!");
        }

        if (options.user != null) {
          if (options.callback) {
            var history = PEER_CONNECTIONS[options.user].history || [[]];

            options.callback([history]);
          } else {
            error("No callback provided for PUBNUB.history");
          }
        } else {
          return _super.apply(this, arguments);
        }
      };
    })(PUBNUB['history']);

    // PUBNUB.peerConnection
    // Returns the current peer connection if one exists
    API['peerConnection'] = function (uuid, callback) {
      if (callback) {
        if (PEER_CONNECTIONS[uuid] != null) {
          callback(PEER_CONNECTIONS[uuid].connection);
        } else {
          callback(null);
        }
      } else {
        debug("PUBNUB.peerConnection should be called with a callback");
      }
    };

    // Closes a peer connection
    function closeConnection(uuid) {
      PEER_CONNECTIONS[uuid].connection.close();
      PEER_CONNECTIONS[uuid] = null;
    };

    // PUBNUB.closeConnection
    // Closes a WebRTC peer connection
    API['closeConnection'] = function (uuid, callback) {
      if (callback != null) {
        if (PEER_CONNECTIONS[uuid] != null) {
          closeConnection(uuid);
        }

        callback(uuid);
      }
    };

    // PUBNUB.dataChannel
    // Returns the current data channel if one exists
    API['dataChannel'] = function (uuid, callback) {
      if (callback) {
        if (PEER_CONNECTIONS[uuid] != null) {
          callback(PEER_CONNECTIONS[uuid].dataChannel);
        } else {
          callback(null);
        }
      } else {
        debug("PUBNUB.dataChannel should be called with a callback");
      }
    };

    // PUBNUB.configurePeerConnection
    // Configures the options when creating a new peer connection internally
    API['configurePeerConnection'] = function (rtcConfig, pcConfig) {
      if (rtcConfig != null) {
        RTC_CONFIGURATION = rtcConfig;
      }

      if (pcConfig != null) {
        PC_OPTIONS = pcConfig;
      }
    };

    return extend(PUBNUB, API);
  }

  // PUBNUB init overload
  PUBNUB['init'] = (function (_super) {
    return function (options) {
      // Grab the UUID
      var uuid = options.uuid || generateUUID();
      options.uuid = uuid;

      // Create pubnub object
      debug("PubNub init: ", options);
      var pubnub = _super.call(this, options);

      // Extend the WebRTC API
      pubnub = extendAPI(pubnub, uuid);
      return pubnub;
    };
  })(PUBNUB['init']);

  var pdiv = document.querySelector("#pubnub");

  if (pdiv) {
    // CREATE A PUBNUB GLOBAL OBJECT
    window.PUBNUB = PUBNUB.init({
      'notest': 1,
      'publish_key': attr(pdiv, 'pub-key'),
      'subscribe_key': attr(pdiv, 'sub-key'),
      'ssl': !document.location.href.indexOf('https') ||
                        attr(pdiv, 'ssl') === 'on',
      'origin': attr(pdiv, 'origin'),
      'uuid': attr(pdiv, 'uuid')
    });
  }

})(window, PUBNUB);
