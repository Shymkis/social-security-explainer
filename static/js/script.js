function formatTime(minutes, seconds) {
  minutes = minutes < 10 ? "0" + minutes : minutes
  seconds = seconds < 10 ? "0" + seconds : seconds
  timer_display.text(minutes + ':' + seconds)
}

function timesUp() {
  if (this.expired()) nextSection()
}

function updateSliderVal(e) {
  let slider = $(e.target)
  let val = slider.val()
  slider.next().text(val)
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

function give_reason(reason) {
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
      $(".your-selection:not(:last)").css("filter","")
      $(".recommendation:not(:last)").css("filter","blur(3px)")
      $(".explanation:not(:last)").css("filter","blur(3px)")
      setTimeout(function() {
        $(".board-container").css("filter","")
        $(".received-msg:not(:last)").css("filter","")
        $(".your-selection:not(:last)").css("filter","")
        $(".recommendation:not(:last)").css("filter","")
        $(".explanation:not(:last)").css("filter","")
      }, 2000)
      scrollChat()
    }, message_content.length*10)
  }
}

function give_recommendation(reason) {
  if (section == "practice") {
    // create message space
    dots = "."
    cur_message.after("<p>" + dots + "</p>")
    cur_message = cur_message.next()
    scrollChat()
    // create message
    let message_content = "Optimal solution"
    // typing animation
    let typing_interval = setInterval(typing, 200)
    setTimeout(function() {
      // stop typing
      clearInterval(typing_interval)
      // display message
      cur_message.html(message_content).addClass("recommendation")
      scrollChat()
      // show correct answer
      give_reason(reason)
    }, message_content.length*10)
  } else {
    give_reason(reason)
  }
}

function explain(reason) {
  explained = true
  let t = chat_display.find(".time").last()
  // create message space
  dots = "."
  t.before("<p>" + dots + "</p>")
  cur_message = t.prev()
  scrollChat()
  // create message
  let message_content = "Test"
  // typing animation
  let typing_interval = setInterval(typing, 200)
  setTimeout(function() {
    // stop typing
    clearInterval(typing_interval)
    // display message
    cur_message.html(message_content).addClass("your-selection")
    scrollChat()
    give_recommendation(reason)
  }, message_content.length*5)
}

function onDrop() {
  // log data
  let selection_data = JSON.stringify({
    scenario_id: scenarios[scenario_num]["id"],
    selection_a: 66,
    selection_b: 66,
    error: 0
  })
  $.ajax({
    url: "/log_selection/",
    type: "POST",
    contentType: "application/json",
    data: selection_data,
    success: function(data) {
      // pulse previous recommendation for repeated mistakes
      if (explained && section == "practice") chat_display.find(".recommendation").last().fadeOut(100).fadeIn(100).fadeOut(100).fadeIn(100)
      // explain the answer
      if ((!explained || section == "testing") && data !== null) explain(data["reason"])
      // continue the scenario accordingly
      explained = false
      let last_message = chat_display.find("p").last()
      last_message.after("Scenario " + (scenario_num + 1) + " completed")
      let t = chat_display.find(".time").last()
      t.html("<hr>")
      scrollChat()
      
      if (section == "practice") {
        scenario_num++
        setTimeout(nextScenario, 500)
      }
    },
    error: function(err) {
      console.log(err)
    }
  })
}

function nextSection() {
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

function nextScenario() {
  if (scenario_num == scenarios.length) {
    nextSection()
    return
  }
  
  chat_display.append(`
    <div class="received-msg">
      Scenario ` + (scenario_num + 1) + ` of ` + scenarios.length + `
      <span class="time"></span>
    </div>
  `)
  scrollChat()
}

function submitSelection() {

}

// undeclared vars
let cur_message, dots, scenarios
// timer vars
let timer_display = $("#timer")
let time_limit = 60*10
let timer = new CountDownTimer(time_limit)
timer.onTick(formatTime).onTick(timesUp)
// slider listeners
$(".slider").on("change", updateSliderVal).on("input", updateSliderVal)
// submit listeners
$("#submit-selection").on("click", submitSelection)
// section vars
let scenario_num = 0
// chat vars
let chat_display = $("#chat")
let explained = false

// get section's scenarios
$.ajax({
  method: "POST",
  url: "/get_scenarios/",
  contentType: "application/json",
  success: function(data) {
    scenarios = data
    if (section == "testing") {
      timer_display.parent().prepend("Testing time remaining: ")
    } else {
      timer_display.parent().prepend("Practice time remaining: ")
    }
    
    nextScenario()
    timer.start()
  },
  error: function(err) {
    console.log(err)
  }
})
