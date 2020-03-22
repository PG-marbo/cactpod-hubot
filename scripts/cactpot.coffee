# Description:
#   Example scripts for you to examine and try out.
#
# Notes:
#   They are commented out by default, because most of them are pretty silly and
#   wouldn't be useful and amusing enough for day to day huboting.
#   Uncomment the ones you want to try and experiment with.

Token  = process.env.HUBOT_SLACK_TOKEN
cheerio = require('cheerio-httpcli')

# くじデータ
roomKujiDatas = {}
roomSecretCircleMap = {}
roomSelectedColumn = {}

# 数字〜絵文字名マップ
numberNameMap = {
  1: "one", 
  2: "two", 
  3: "three", 
  4: "four", 
  5: "five", 
  6: "six", 
  7: "seven", 
  8: "eight", 
  9: "nine", 
}

# マス選択絵文字
secretCircleEmojis = {
  1: {
    1: "shiro_a",
    2: "shiro_b",
    3: "shiro_c",
  },
  2: {
    1: "shiro_d",
    2: "shiro_e",
    3: "shiro_f",
  },
  3: {
    1: "shiro_g",
    2: "shiro_h",
    3: "shiro_i",
  },
}

# 獲得MGPマスタ
mgpMaster = {
  6: 10000,
  7: 36,
  8: 720,
  9: 360,
  10: 80,
  11: 252,
  12: 108,
  13: 72,
  14: 54,
  15: 180,
  16: 72,
  17: 180,
  18: 119,
  19: 36,
  20: 306,
  21: 1080,
  22: 144,
  23: 1800,
  24: 3600,
}

# ライン選択と開く場所
arrowLocationMap = [
  {name: 'arrow_lower_right', type: 'down_right', location: [0, 1, 2],}
  {name: 'arrow_lower1', type: 'down', location: 0,}
  {name: 'arrow_lower2', type: 'down', location: 1,}
  {name: 'arrow_lower3', type: 'down', location: 2,}
  {name: 'arrow_right1', type: 'right', location: 1,}
  {name: 'arrow_right2', type: 'right', location: 2,}
  {name: 'arrow_right3', type: 'right', location: 3,}
]

module.exports = (robot) ->

  robot.respond /ミニくじテンダー/i, (res) ->
    room = res.message.room
    state = robot.brain.get "kuji_state_#{room}"

    if !state
      state = "game_start"

    else if state != "game_finished"
      res.send "まだゲーム中です"
      return

    sendMessage("ミニくじテンダーSTART!\nリアクションから、削るマスを `3つ` 選んでください", room)

    {kujiDatas, openNumber} = kujiDataGenerate(room)

    visibleText = ""
    for datas in kujiDatas
      for visibleData, i in datas.visibleDatas
        visibleText += visibleData
        if i == 3
          visibleText += "\n"

    sendRes = sendMessage(visibleText, room)

    numberSelectTS = JSON.parse(sendRes.body).ts
    robot.brain.set "kuji_update_ts_#{room}", numberSelectTS

    addNumberSelectReaction(numberSelectTS, room, openNumber)

    roomKujiDatas[room] = kujiDatas

    robot.brain.set "kuji_state_#{room}", "data_generate_done"

  # リアクション取得
  robot.hearReaction (res) ->
    if res.message.type != 'added'
      return

    state = robot.brain.get "kuji_state_#{res.message.room}"
    
    room     = res.message.room
    reaction = res.message.reaction

    if state == "data_generate_done"
      selectNumber(robot, reaction, room)
      return

    if state == "columns_selected_init_done"
      selectColumns(robot, reaction, res.message.user.id, room)
      return

# くじ更新
selectNumber = (robot, reaction, room) ->
  switch reaction
    when 'shiro_a', 'shiro_b', 'shiro_c', 'shiro_d', 'shiro_e', 'shiro_f', 'shiro_g', 'shiro_h', 'shiro_i'

      selectedNumberCount = robot.brain.get "kuji_number_selected_count_#{room}"
      
      if !selectedNumberCount
        selectedNumberCount = 0

      robot.brain.set "kuji_number_selected_count_#{room}", (selectedNumberCount + 1)

      if !updateKujiDatasForOpenNumber(reaction, room)
        return

      ts = robot.brain.get "kuji_update_ts_#{room}"
      
      if !ts
        return false

      if !updateDrawKuji(room, ts)
        return

      if selectedNumberCount >= 2
        robot.brain.set "kuji_state_#{room}", "number_selected_done"

        initSelectedColumns(robot, room)
        return

    else
      return

# 列選択発言
initSelectedColumns = (robot, room) ->
  sendMessage('リアクションからラインを `1つ` 選んでください', room)

  kujiDatas = roomKujiDatas[room]
  visibleText = ""
  for datas in kujiDatas
    for visibleData, i in datas.visibleDatas
      visibleText += visibleData
      if i == 3
        visibleText += "\n"

  sendRes = sendMessage(visibleText, room)

  ts = JSON.parse(sendRes.body).ts
  robot.brain.set "kuji_update_ts_#{room}", ts

  addColumnsSelectReaction(ts, room)

  robot.brain.set "kuji_state_#{room}", "columns_selected_init_done"

# 列選択
selectColumns = (robot, reaction, reactionUserID, room) ->
  switch reaction
    when 'arrow_lower_right', 'arrow_lower1', 'arrow_lower2', 'arrow_lower3', 'arrow_right1', 'arrow_right2', 'arrow_right3'
      selectedColumnCount = robot.brain.get "kuji_column_selected_count_#{room}"
      
      if !selectedColumnCount
        selectedColumnCount = 0

      robot.brain.set "kuji_columns_selected_count_#{room}", (selectedColumnCount + 1)

      if !updateKujiDatasForSelectColumn(reaction, room)
        return

      ts = robot.brain.get "kuji_update_ts_#{room}"
      
      if !ts
        return false

      if !updateDrawKuji(room, ts)
        return

      selectedNumber = ""
      numberTotal = 0
      for numberData in roomSelectedColumn[room]
        selectedNumber += "#{numberData.visible}"
        numberTotal += numberData.number

      mgpList = robot.brain.get 'get_mgp_list'

      if !mgpList
        mgpList = {}

      if !mgpList[reactionUserID]
        mgpList[reactionUserID] = mgpMaster[numberTotal]
      else
        mgpList[reactionUserID] += mgpMaster[numberTotal]
        
      robot.brain.set 'get_mgp_list', mgpList 

      sendMessage "<@#{reactionUserID}>\n Selected: #{selectedNumber}\n `#{mgpMaster[numberTotal]}` MGP GET ♪ \n Total MGP: #{mgpList[reactionUserID]}", room

      if selectedColumnCount >= 0
        robot.brain.set "kuji_state_#{room}", "game_finished"
        robot.brain.set "kuji_number_selected_count_#{room}", 0
        robot.brain.set "kuji_columns_selected_count_#{room}", 0
        roomKujiDatas[room] = null
        roomSecretCircleMap[room] = []
    else
      return

# くじ列選択データ更新
updateKujiDatasForSelectColumn = (reaction, room) ->
  kujiDatas = roomKujiDatas[room]

  find = arrowLocationMap.find((data) ->
    return data.name == reaction
  )

  selectedNumbers = []

  if !find
    return false
  
  for record, i in kujiDatas
    if i == 0
      continue

    for number, j in record.numberDatas
      if find.type == 'down'
        if find.location != j
          continue

        record.visibleDatas[j+1] = ":#{numberNameMap[record.numberDatas[j]]}:"
        selectedNumbers.push {visible: ":#{numberNameMap[record.numberDatas[j]]}:", number: record.numberDatas[j]}
        continue
        
      if find.type == 'right'
        if find.location != i
          continue

        record.visibleDatas[j+1] = ":#{numberNameMap[record.numberDatas[j]]}:"
        selectedNumbers.push {visible: ":#{numberNameMap[record.numberDatas[j]]}:", number: record.numberDatas[j]}
        continue

      if find.type == 'down_right'
        if i == 1 && j == 0
          record.visibleDatas[j+1] = ":#{numberNameMap[record.numberDatas[j]]}:"
          selectedNumbers.push {visible: ":#{numberNameMap[record.numberDatas[j]]}:", number: record.numberDatas[j]}
          continue

        if i == 2 && j == 1
          record.visibleDatas[j+1] = ":#{numberNameMap[record.numberDatas[j]]}:"
          selectedNumbers.push {visible: ":#{numberNameMap[record.numberDatas[j]]}:", number: record.numberDatas[j]}
          continue

        if i == 3 && j == 2
          record.visibleDatas[j+1] = ":#{numberNameMap[record.numberDatas[j]]}:"
          selectedNumbers.push {visible: ":#{numberNameMap[record.numberDatas[j]]}:", number: record.numberDatas[j]}
          continue

  roomKujiDatas[room] = kujiDatas
  roomSelectedColumn[room] = selectedNumbers

  return true

# くじデータ作成
kujiDataGenerate = (room) ->
  kujiDatas  = []
  numbers    = random([1, 2, 3, 4, 5, 6, 7, 8, 9])
  openNumber = random([1, 2, 3, 4, 5, 6, 7, 8, 9])[0]
  arrowEmojis = [
    'arrow_lower1',
    'arrow_lower2',
    'arrow_lower3',
    'arrow_right1',
    'arrow_right2',
    'arrow_right3',
  ]
  
  secretCircleMap = []

  for i in [0..3]
    kujiData = {
      numberDatas: [],     # 数字データ
      visibleDatas: [],    # 表示データ
      selectedColumns: [], # 選択済みの列
    }

    for j in [0..3]
      if i == 0 
        if j == 0
          kujiData.visibleDatas.push ':arrow_lower_right:'
          continue

        kujiData.visibleDatas.push ":#{arrowEmojis[0]}:"
        arrowEmojis.shift()
        continue

      if j == 0
        kujiData.visibleDatas.push ":#{arrowEmojis[0]}:"
        arrowEmojis.shift()
        continue

      number = numbers[0]

      kujiData.numberDatas.push number
      numbers.shift()

      secretCircleMap.push {number: number, name: secretCircleEmojis[i][j]}

      isOpen = false
      if openNumber == number
        isOpen = true

      if isOpen 
        kujiData.visibleDatas.push ":#{numberNameMap[openNumber]}:"
      else
        kujiData.visibleDatas.push ":#{secretCircleEmojis[i][j]}:"

    kujiDatas.push kujiData

  secretCircleMap.sort (a, b) ->
    if a.name < b.name
      return -1
    if a.name > b.name
      return 1
    return 0

  roomSecretCircleMap[room] = secretCircleMap

  return {kujiDatas, openNumber}     

# くじデータ更新
updateKujiDatasForOpenNumber = (reaction, room) ->
  kujiDatas = roomKujiDatas[room]
  secretCircleMap = roomSecretCircleMap[room]

  find = secretCircleMap.find((data) ->
    return data.name == reaction
  )

  if !find
    return false
  
  for record, i in kujiDatas
    for number, j in record.numberDatas
      if number != find.number
        continue

      record.visibleDatas[j+1] = ":#{numberNameMap[find.number]}:"

  roomKujiDatas[room] = kujiDatas

  return true

# くじ描画更新
updateDrawKuji = (room, ts) ->
  kujiDatas = roomKujiDatas[room]
      
  visibleText = ""
  for datas in kujiDatas
    for visibleData, i in datas.visibleDatas
      visibleText += visibleData
      if i == 3
        visibleText += "\n"

  request = {
    token: Token,
    channel: room,
    text: visibleText,
    ts: ts,
    as_user: true,
  }

  res = cheerio.fetchSync "https://slack.com/api/chat.update", request
  return JSON.parse(res.body).ok

# 数字選択リアクション
addNumberSelectReaction = (ts, room, openNumber) ->
  request = {
    token: Token,
    channel: room,
    name: "",
    timestamp: ts,
  }

  for reaction in roomSecretCircleMap[room]
    if reaction.number == openNumber
      continue
    request.name = reaction.name
    cheerio.fetchSync "https://slack.com/api/reactions.add", request

# 数字選択リアクション
addColumnsSelectReaction = (ts, room) ->
  request = {
    token: Token,
    channel: room,
    name: "",
    timestamp: ts,
  }

  for data in arrowLocationMap
    request.name = data.name
    cheerio.fetchSync "https://slack.com/api/reactions.add", request

# メッセージ送信
sendMessage = (text, room) ->
  request = {
    token: Token,
    channel: room,
    text: text,
    as_user: true,
  }

  return cheerio.fetchSync "https://slack.com/api/chat.postMessage", request

# ランダム
random = (array) ->
  i = array.length - 1
  while i > 0
    r = Math.floor(Math.random() * (i + 1))
    tmp = array[i]
    array[i] = array[r]
    array[r] = tmp
    i--

  return array
