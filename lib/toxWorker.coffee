toxcore = require 'toxcore'
fs      = require 'fs'

BigMessage = require './botProtocol/prot-bigMessage'

module.exports =
class ToxWorker
  constructor: (params) ->
    @ntb      = params.ntb
    @saveFile = params.saveFile
    @name     = params.name
    @status   = params.status
    @nodes    = params.nodes
    @consts   = toxcore.Consts

  startup: ->
    toxOpts = {'data': @getSave @saveFile } if fs.existsSync @saveFile
    @tox = new toxcore.Tox toxOpts

    @setNameAndStatus  @name, @status
    @tox.setStatusSync 0 # TODO: use cons

    # Register event handler
    @tox.on 'friendRequest',          (evt) => @handleFriendRequest          evt
    @tox.on 'friendMessage',          (evt) => @handleFriendMessage          evt
    @tox.on 'friendConnectionStatus', (evt) => @handleFriendConnectionStatus evt
    @tox.on 'selfConnectionStatus',   (evt) => @handleSelfConnectionStatus   evt

    @deleteAllFriends()

    @tox.bootstrapSync i.address, i.port, i.key for i in @nodes

    console.log "TOX id: #{@tox.getAddressHexSync()}"
    @tox.start()

  deleteAllFriends: -> # TODO renmove this when ID's wont change anymore
    for i in @tox.getFriendListSync()
      @tox.deleteFriendSync i
      console.log "Deleted Friend #{i}"

  setNameAndStatus: (name, status) ->
    @tox.setNameSync          name
    @tox.setStatusMessageSync status

  handleFriendRequest: (evt) ->
    fID = @tox.addFriendNoRequestSync evt.publicKey()
    @ntb.addFriend {
      "id":      fID
      "pubKey":  evt.publicKey()
      "sendCB":  (msg) => @sendCMD fID, msg
    }

    console.log "Accepted friend request from #{evt.publicKeyHex()}"

  handleFriendMessage: (evt) ->
    return unless evt.messageType() is @consts.TOX_MESSAGE_TYPE_ACTION
    if not @ntb.friends[evt.friend()]?
      console.log "Fatal error: Friend #{evt.friend()} not found"
      console.log "  MSG: #{evt.message()}"
      return
    BigMessage.receive evt.message(), (msg) =>
      @ntb.friends[evt.friend()].pReceivedCommand evt.message()

  handleFriendConnectionStatus: (evt) ->
    unless evt.connectionStatus() is @consts.TOX_CONNECTION_NONE
      console.log "#{evt.friend()} is now Online"
      if @ntb.friends[evt.friend()]?
        @ntb.friends[evt.friend()].online()
      else
        console.log "Friend #{evt.friend()} is Undefined!"
      return
    console.log "#{evt.friend()} is now ofline"

  handleSelfConnectionStatus: (evt) ->
    if evt.isConnected()
      console.log "Connected"
    else
      console.log "Disconnected"

  sendCMD: (fID, msg) ->
    try
      return BigMessage.send msg, @consts.TOX_MAX_MESSAGE_LENGTH, (m) =>
        @tox.sendFriendMessageSync fID, m, @consts.TOX_MESSAGE_TYPE_ACTION
    catch e
      console.log "ERROR: Failed to send message"
      console.log "  Friend ID: #{fID}"
      console.log "  Message:   #{msg}"
      console.log e
      return -1

  getSave: (file) ->
    stats = fs.statSync file
    return fs.readFileSync file if stats.isFile()
    return null

  shutdown: ->
    console.log " - shutting down TOX..."
    fs.writeFileSync @saveFile, @tox.getSavedataSync()
    @tox.killSync()
