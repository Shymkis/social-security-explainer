function formatTime(minutes, seconds) {
  minutes = minutes < 10 ? "0" + minutes : minutes
  seconds = seconds < 10 ? "0" + seconds : seconds
  timer_display.text(minutes + ':' + seconds)
}

function timesUp() {
  if (this.expired()) nextSection()
}

function removeGreySquares() {
  $('#board .square-55d63').css('background', '')
}

function removeGreenSquares() {
  $('#board .square-55d63').css('box-shadow', '')
}

function greySquare(square) {
  let square_display = $('#board .square-' + square)
  let background = whiteSquareGrey
  if (square_display.hasClass('black-3c85d')) background = blackSquareGrey
  square_display.css('background', background)
}

function greenSquare(square) {
  let square_display = $('#board .square-' + square)
  square_display.css('box-shadow', 'inset 0 0 3px 3px' + squareGreen)
}

function makePuzzleMove() {
  game.move(moves[move_num], { sloppy: true })
  board.position(game.fen())
  move_num++
  move_start = Date.now()
}

function scrollChat() {
  let scroll_height = 0
  chat_display.children().each(function() { scroll_height += $(this).height() })
  chat_display.animate({ scrollTop: scroll_height })
}

function typing() {
  dots = dots == "..." ? "." : dots + "."
  cur_message.text(dots)
}

function give_explanation(reason) {
  if (protocol != "none") {
    // create message space
    dots = "."
    cur_message.after("<p>" + dots + "</p>")
    cur_message = cur_message.next()
    scrollChat()
    // create message
    let message_content = protocol == "none" ? "" : ("<b>My explanation:</b> " + reason)
    // typing animation
    let typing_interval = setInterval(typing, 200)
    setTimeout(function() {
      // stop typing
      clearInterval(typing_interval)
      // display message
      cur_message.html(message_content).css({"background-color": "#00a", "color": "#efefef"}).addClass("explanation")

      $(".board-container").css("filter","blur(3px)")
      $(".received-msg:not(:last)").css("filter","blur(3px)")
      $(".your-move:not(:last)").css("filter","")
      $(".recommendation:not(:last)").css("filter","blur(3px)")
      $(".explanation:not(:last)").css("filter","blur(3px)")
      setTimeout(function() {
        $(".board-container").css("filter","")
        $(".received-msg:not(:last)").css("filter","")
        $(".your-move:not(:last)").css("filter","")
        $(".recommendation:not(:last)").css("filter","")
        $(".explanation:not(:last)").css("filter","")
      }, 2000)
      scrollChat()
    }, message_content.length*10)
  }
}

function give_recommendation(c_source, c_target, mistake, reason) {
  if (mistake && section == "practice") {
    // create message space
    dots = "."
    cur_message.after("<p>" + dots + "</p>")
    cur_message = cur_message.next()
    scrollChat()
    // create message
    let message_content = "<b>My recommendation:</b> " + piece_names[game.get(c_source).type] + " to " + c_target
    // typing animation
    let typing_interval = setInterval(typing, 200)
    setTimeout(function() {
      // stop typing
      clearInterval(typing_interval)
      // display message
      cur_message.html(message_content).addClass("recommendation")
      scrollChat()
      // show move
      if (section == "practice" && mistake) {
        greenSquare(c_source)
        greenSquare(c_target)
      }
      give_explanation(reason)
    }, message_content.length*10)
  } else {
    give_explanation(reason)
  }
}

function explain(h_source, h_target, mistake, reason) {
  explained_move = true
  let t = chat_display.find(".time").last()
  // create message space
  dots = "."
  t.before("<p>" + dots + "</p>")
  cur_message = t.prev()
  scrollChat()
  // create message
  let c_source = moves[move_num].slice(0,2)
  let c_target = moves[move_num].slice(-2)
  let h_piece = mistake ? piece_names[game.get(h_source).type] : piece_names[game.get(h_target).type]
  let mark = mistake ? " <span class='cross'>&#10006</span>" : " <span class='check'>&#10004</span>"
  let message_content = "<b>Your move:</b> " + h_piece + " to " + h_target + mark
  // typing animation
  let typing_interval = setInterval(typing, 200)
  setTimeout(function() {
    // stop typing
    clearInterval(typing_interval)
    // display message
    cur_message.html(message_content).addClass("your-move")
    scrollChat()
    give_recommendation(c_source, c_target, mistake, reason)
  }, message_content.length*5)
}

function onDragStart(source, piece, position, orientation) {
  // do not pick up pieces if the game is over
  if (game.game_over()) return false

  // do not pick up pieces if it's not the player's turn
  if (game.turn() != player_c) return false

  // only pick up pieces for player color
  if (!piece.startsWith(player_c)) return false

  removeGreySquares()
  // get list of possible moves for this square
  let legal_moves = game.moves({
    square: source,
    verbose: true
  })
  // exit if there are no moves available for this square
  if (legal_moves.length === 0) return
  // highlight the square they moused over
  greySquare(source)
  // highlight the possible squares for this piece
  for (let i = 0; i < legal_moves.length; i++) {
    greySquare(legal_moves[i].to)
  }
}

function logThemeAnswer(button, p_id, user_response) {
  $(button).siblings().removeClass("highlight")
  $(button).addClass("highlight")

  answer_data = JSON.stringify({
    puzzle_id: p_id,
    user_answer: user_response,
    correct_answer: theme,
    correct: user_response == theme
  })
  $.ajax({
    url: "/log_theme_answer/",
    type: "POST",
    contentType: "application/json",
    data: answer_data,
    success: function(data) {
      if (p_id == puzzles[puzzle_num]["id"]) {
        puzzle_num++
        setTimeout(nextPuzzle, 500)
      }
    },
    error: function(err) {
      console.log(err)
    }
  })
}

function themeQuestion() {
  question_html = `
    <div class="testing-question" style="display: flex">
      What was the tactic used in this puzzle?
      <div class="testing-answer" style="display: flex">
        <button type="button" onclick="logThemeAnswer(this, ` + puzzles[puzzle_num]["id"] + `, 'fork')">Fork</button>
        <button type="button" onclick="logThemeAnswer(this, ` + puzzles[puzzle_num]["id"] + `, 'pin')">Pin</button>
      </div>
    </div>
  `
  let last_message = chat_display.find("p").last()
  last_message.after(question_html)
}

function onDrop(source, target) {
  removeGreySquares()

  // see if the move is legal
  let move = game.move({
    from: source,
    to: target,
    promotion: 'q' // NOTE: always promote to a queen for example simplicity
  })

  // illegal move
  if (move === null) return "snapback"

  // legal move
  let move_end = Date.now()
  num_moves++
  move_string = move.from + move.to
  let mistake = move_string != moves[move_num]
  // wrong or right move
  if (mistake) {
    num_mistakes++
  } else {
    completed = (move_num + 1 == moves.length)
  }
  if (completed && num_mistakes == 0) successes++
  // log data
  let move_data = JSON.stringify({
    puzzle_id: puzzles[puzzle_num]["id"],
    move_num: move_num,
    move: move_string,
    move_start: move_start,
    move_end: move_end,
    move_duration: move_end - move_start,
    mistake: mistake,
    // section data
    section_start: section_start,
    section_end: move_end,
    section_duration: move_end - section_start,
    num_moves: num_moves,
    successes: successes,
    puzzles: completed ? puzzle_num + 1 : puzzle_num
  })
  $.ajax({
    url: "/log_move/",
    type: "POST",
    contentType: "application/json",
    data: move_data,
    success: function(data) {
      // undo wrong move
      if (mistake) game.undo()
      // pulse previous recommendation for repeated mistakes
      if (explained_move && mistake && section == "practice") chat_display.find(".recommendation").last().fadeOut(100).fadeIn(100).fadeOut(100).fadeIn(100)
      // explain move
      if ((!explained_move || section == "testing") && data !== null) explain(source, target, mistake, data["reason"])
      // continue the puzzle accordingly
      if (mistake) {
        // start new move timer on wrong move
        move_start = Date.now()
      } else {
        // make next puzzle move after correct move
        move_num++
        explained_move = false
        removeGreenSquares()
        if (completed) {
          let last_message = chat_display.find("p").last()
          last_message.after("Puzzle " + (puzzle_num + 1) + " completed")
          let t = chat_display.find(".time").last()
          t.html("<hr>")
          scrollChat()
          
          if (section == "practice") {
            puzzle_num++
            setTimeout(nextPuzzle, 500)
          } else {
            themeQuestion()
          }
        } else {
          setTimeout(makePuzzleMove, 250)
        }
      }
    },
    error: function(err) {
      console.log(err)
    }
  })
  if (mistake) return "snapback"
}

function onMouseoverSquare(square, piece) {
  // do not show moves if it's not the player's turn
  if (game.turn() != player_c) return false

  // only show moves for player color
  if (piece && !piece.startsWith(player_c)) return false

  // get list of possible moves for this square
  let legal_moves = game.moves({
    square: square,
    verbose: true
  })

  // exit if there are no moves available for this square
  if (legal_moves.length === 0) return

  // highlight the square they moused over
  greySquare(square)

  // highlight the possible squares for this piece
  for (let i = 0; i < legal_moves.length; i++) {
    greySquare(legal_moves[i].to)
  }
}

function onMouseoutSquare(square, piece) {
  removeGreySquares()
}

function nextSection() {
  let section_end = Date.now()
  section_data = JSON.stringify({
    end_time: section_end,
    duration: section_end - section_start
  })
  $.ajax({
    method: "POST",
    url: "/log_section/",
    contentType: "application/json",
    data: section_data,
    success: function(next_section) {
      if (section == "practice") alert("Now entering the Testing section!")
      location.replace(next_section)
    },
    error: function(err) {
      console.log(err)
    }
  })
}

function nextPuzzle() {
  if (puzzle_num == puzzles.length) {
    nextSection()
    return
  }

  fen = puzzles[puzzle_num]["fen"]
  moves = puzzles[puzzle_num]["moves"].split(" ")
  theme = puzzles[puzzle_num]["theme"]
  
  game = new Chess(fen)
  player_c = game.turn()
  player_color = player_c == 'w' ? "white" : "black"
  move_num = 0, num_mistakes = 0, completed = false
  if (puzzle_num == 0) section_start = Date.now()
  
  chat_display.append(`
    <div class="received-msg">
      Puzzle ` + (puzzle_num + 1) + ` of ` + puzzles.length + `
      <span class="time"></span>
    </div>
  `)
  scrollChat()

  let config = {
    draggable: true,
    position: fen,
    orientation: player_color,
    onDragStart: onDragStart,
    onDrop: onDrop,
    onMouseoutSquare: onMouseoutSquare,
    onMouseoverSquare: onMouseoverSquare
  }
  board = Chessboard("board", config)
  move_start = Date.now()
}

// undeclared vars
let board, completed, cur_message, dots, fen, game, move_num, move_start, move_string, moves, num_mistakes, player_c, player_color, puzzles, rating, section_start, theme
// timer vars
let timer_display = $("#timer")
let time_limit = 60*10
let timer = new CountDownTimer(time_limit)
timer.onTick(formatTime).onTick(timesUp)
// board vars
let piece_names = {b: "Bishop", k: "King", n: "Knight", p: "Pawn", q: "Queen", r: "Rook"}
let whiteSquareGrey = '#a9a9a9', blackSquareGrey = '#696969', squareGreen = '#0a0'
// section vars
let puzzle_num = 0, successes = 0, num_moves = 0
// chat vars
let chat_display = $("#chat")
let explained_move = false

// get section's puzzles
$.ajax({
  method: "POST",
  url: "/get_puzzles/",
  contentType: "application/json",
  success: function(data) {
    puzzles = data
    if (section == "testing") {
      timer_display.parent().prepend("Testing time remaining: ")
      chat_display.append(`
        <div class="received-msg">
          <p>Test your skills on these new puzzles without any help from me. Keep trying until you find the right move. <b>Your reward increases with the number of puzzles completed and decreases with the number of mistakes made.</b></p>
          <span class="time"><hr></span>
        </div>
      `)
    } else {
      timer_display.parent().prepend("Practice time remaining: ")
      chat_display.append(`
        <div class="received-msg">
          <p>Hello! I am your AI agent. I'm here to assist you with these puzzles.</p>
          <span class="time"><hr></span>
        </div>
      `)
    }
    
    nextPuzzle()
    timer.start()
  },
  error: function(err) {
    console.log(err)
  }
})
