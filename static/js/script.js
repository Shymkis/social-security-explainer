function formatTime(minutes, seconds) {
  minutes = minutes < 10 ? "0" + minutes : minutes
  seconds = seconds < 10 ? "0" + seconds : seconds
  timer_display.text(minutes + ':' + seconds)
}

function timesUp() {
  if (this.expired()) nextSection()
}

function updateSliderVal() {
  let slider = $(this)
  if (slider.val() < 62) {
    slider.val(62)
  } else if (slider.val() > 70) {
    slider.val(70)
  }
  slider.siblings("output").text(slider.val())
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
  // create message space
  let t = chat_display.find(".time").last()
  dots = "."
  t.before("<p>" + dots + "</p>")
  cur_message = t.prev()
  scrollChat()
  // create message
  let message_content = "<b>My explanation:</b> " + reason
  // typing animation
  let typing_interval = setInterval(typing, 200)
  setTimeout(function() {
    // stop typing
    clearInterval(typing_interval)
    // display message
    cur_message.html(message_content).css({"background-color": "#00a", "color": "#efefef"}).addClass("explanation")
    scrollChat()
  }, message_content.length*10)
}

function submitSelection() {
  // calculate error (and bonus if testing)
  let married = scenarios[scenario_num]["marital_status"] == "married"

  let selection_a = $("#spouse_a").val()
  let optimal_age_a = scenarios[scenario_num]["optimal_age_a"]
  let error_a = Math.abs(selection_a - optimal_age_a)
  let bonus_a = section == "testing" ? (1/18)*Math.max(0, 1 - error_a/4) : null

  let selection_b = null
  let optimal_age_b = null
  let error_b = null
  let bonus_b = null
  if (married) {
    selection_b = $("#spouse_b").val()
    optimal_age_b = scenarios[scenario_num]["optimal_age_b"]
    error_b = Math.abs(selection_b - optimal_age_b)
    if (section == "testing") bonus_b = (1/18)*Math.max(0, 1 - error_b/4)
  }
  // log data
  let selection_data = JSON.stringify({
    scenario_id: scenarios[scenario_num]["id"],
    selection_a: selection_a,
    error_a: error_a,
    bonus_a: bonus_a,
    selection_b: selection_b,
    error_b: error_b,
    bonus_b: bonus_b
  })
  $.ajax({
    url: "/log_selection/",
    type: "POST",
    contentType: "application/json",
    data: selection_data,
    success: function(data) {
      // post-selection changes
      $(".slider").prop("disabled", true)
      $("#optimal_a").text(optimal_age_a)
      $("#error_a").text(error_a)
      if (section == "testing") $("#bonus_a").text((100*bonus_a).toFixed(1) + "¢")
      if (married) {
        $("#optimal_b").text(optimal_age_b)
        $("#error_b").text(error_b)
        if (section == "testing") $("#bonus_b").text((100*bonus_b).toFixed(1) + "¢")
      }
      // give recommendation if practice
      // if (section == "practice" && data !== null) give_reason(data["reason"])
      if (section == "practice") give_reason("Test")
    },
    error: function(err) {
      console.log(err)
    }
  })
}

function clickedSubmit() {
  let submit_button = $("#submit")
  switch (submit_button.text()) {
    case "Submit":
      submitSelection()
      submit_button.text("Continue")
      break
    case "Continue":
      // move on to the next scenario
      scenario_num++
      let last_message = chat_display.find("p").last()
      last_message.after("Scenario " + scenario_num + " completed")
      let t = chat_display.find(".time").last()
      t.html("<hr>")
      scrollChat()
      nextScenario()
      submit_button.text("Submit")
      break
  }
  // disable button for 5 seconds
  submit_button.prop("disabled", true)
  setTimeout(function() { submit_button.prop("disabled", false) }, 1000)
}

function nextSection() {
  $.ajax({
    method: "POST",
    url: "/log_section/",
    contentType: "application/json",
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
  
  $("#scenario").text("Scenario " + (scenario_num + 1) + " of " + scenarios.length)

  let scenario = scenarios[scenario_num]
  let married = scenario["marital_status"] == "married"
  let len_a = len_b = 100
  if (married) {
    let a_over_b = (scenario["life_expectancy_a"] - scenario["current_age_a"])/(scenario["life_expectancy_b"] - scenario["current_age_b"])
    len_a = 100*Math.min(1, a_over_b)
    len_b = 100*Math.min(1, 1/a_over_b)
  }
  $(".data-row").remove()
  $("#board table tr:last").after(`
    <tr class="data-row">
      <th scope="row">Spouse A</th>
      <td>$` + scenario["pia_a"] + `</td>
      <td class="slider-cell">
        <output style="width: ` + len_a + `%">66</output>
        <input type="range" min="` + scenario["current_age_a"] + `" max="` + scenario["life_expectancy_a"] + `" value="66" list="markers_a" class="slider" id="spouse_a" style="width: ` + len_a + `%">
        <datalist id="markers_a" style="width: ` + len_a + `%">
          <option value="` + scenario["current_age_a"] + `" label="` + scenario["current_age_a"] + `"></option>
          <option value="62"></option>
          <option value="70"></option>
          <option value="` + scenario["life_expectancy_a"] + `" label="` + scenario["life_expectancy_a"] + `"></option>
        </datalist>
      </td>
      <td id="optimal_a"></td>
      <td id="error_a"></td>
      ` + (section == "testing" ? `<td id="bonus_a"></td>` : ``) + `
    </tr>
  `)
  if (married) {
    $("#board table tr:last").after(`
    <tr class="data-row">
      <th scope="row">Spouse B</th>
      <td>$` + scenario["pia_b"] + `</td>
      <td class="slider-cell">
        <output style="width: ` + len_b + `%">66</output>
        <input type="range" min="` + scenario["current_age_b"] + `" max="` + scenario["life_expectancy_b"] + `" value="66" list="markers_b" class="slider" id="spouse_b" style="width: ` + len_b + `%">
        <datalist id="markers_b" style="width: ` + len_b + `%">
          <option value="` + scenario["current_age_b"] + `" label="` + scenario["current_age_b"] + `"></option>
          <option value="62"></option>
          <option value="70"></option>
          <option value="` + scenario["life_expectancy_b"] + `" label="` + scenario["life_expectancy_b"] + `"></option>
        </datalist>
      </td>
      <td id="optimal_b"></td>
      <td id="error_b"></td>
      ` + (section == "testing" ? `<td id="bonus_b"></td>` : ``) + `
    </tr>
  `)
  }

  chat_display.append(`
    <div class="received-msg">
      Scenario ` + (scenario_num + 1) + `
      <span class="time"></span>
    </div>
  `)
  scrollChat()
}

// undeclared vars
let cur_message, scenarios
// timer vars
let timer_display = $("#timer")
let time_limit = 60*10
let timer = new CountDownTimer(time_limit)
timer.onTick(formatTime).onTick(timesUp)
// slider listeners
$(document).on("change input", ".slider", updateSliderVal)
// submit listeners
$("#submit").on("click", clickedSubmit)
// section vars
let scenario_num = 0
// chat vars
let chat_display = $("#chat")
let dots = "."

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
