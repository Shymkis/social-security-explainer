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

function typing() {
  dots = dots == "●●●" ? '●' : dots + '●'
  cur_message.text(dots)
}

async function explain(reasons, selection) {
  // create message space
  $("#submit").before(`
    <div class="chat-container">
      <div class="chatbox">
        <div class="msg-header">
          <img src="/static/img/avatars/xai-avatar.png">
          <div class="active">
            <p>AI Agent</p>
          </div>
        </div>
        <div class="msg-inbox" style="color: #646464"></div>
      </div>
    </div>
  `)
  let tags = new explanation_tags(scenarios[scenario_num], selection)
  for (let i = 0; i < reasons.length; i++) {
    let reason = reasons[i]
    // insert tags into reason
    reason = tags.replace_in(reason)
    dots = '●'
    chat_display().append(`
      <div class="received-msg">
        <p style="background-color: #00a; color: #efefef">` + dots + `</p>
      </div>
    `)
    cur_message = chat_display().find("p").last()
    // typing animation
    let typing_interval = setInterval(typing, 200)
    await sleep(reason.length*5)
    // stop typing
    clearInterval(typing_interval)
    // display message
    cur_message.html(reason).css({"background-color": "#00a", "color": "#efefef"}).addClass("explanation")
  }
  // enable button after a delay
  setTimeout(function() { $("#submit").prop("disabled", false) }, 3000)
}

function submitSelection() {
  // calculate error (and bonus if testing)
  let scenario = scenarios[scenario_num]
  let married = scenario["marital_status"] == "married"

  let selection_a = $(".spouse_a").last().val()
  let optimal_age_a = scenario["optimal_age_a"]
  let error_a = Math.abs(selection_a - optimal_age_a)
  let bonus_a = section == "testing" ? (1/18)*Math.max(0, 1 - error_a/4) : null

  let selection_b = null
  let optimal_age_b = null
  let error_b = null
  let bonus_b = null
  if (married) {
    selection_b = $(".spouse_b").last().val()
    optimal_age_b = scenario["optimal_age_b"]
    error_b = Math.abs(selection_b - optimal_age_b)
    if (section == "testing") bonus_b = (1/18)*Math.max(0, 1 - error_b/4)
  }
  // log data
  let selection_data = JSON.stringify({
    scenario_id: scenario["id"],
    selection_a: selection_a,
    error_a: error_a,
    bonus_a: bonus_a,
    selection_b: selection_b,
    error_b: error_b,
    bonus_b: bonus_b,
    theme: scenario["theme"]
  })
  $.ajax({
    url: "/log_selection/",
    type: "POST",
    contentType: "application/json",
    data: selection_data,
    success: function(data) {
      // post-selection changes
      $(".slider").prop("disabled", true)
      $(".optimal_a").last().text(optimal_age_a)
      $(".error_a").last().text(error_a)
      if (section == "testing") $(".bonus_a").last().text((bonus_a > 0 ? `~` : '') + Math.trunc(100*bonus_a) + '¢')
      if (married) {
        $(".optimal_b").last().text(optimal_age_b)
        $(".error_b").last().text(error_b)
        if (section == "testing") $(".bonus_b").last().text((bonus_b > 0 ? `~` : '') + Math.trunc(100*bonus_b) + '¢')
      }
      // give explanation if right protocol
      if (protocol != "none" && data !== null) {
        explain(data, JSON.parse(selection_data))
      } else {
        // enable button after a delay
        setTimeout(function() { $("#submit").prop("disabled", false) }, 1000)
      }
    },
  error: function(err) {
    console.log(err)
    }
  })
}

function clickedSubmit() {
  let submit_button = $("#submit")
  // disable button
  submit_button.prop("disabled", true)
  // perform corresponding action
  switch (submit_button.text()) {
    case "Submit":
      submitSelection()
      submit_button.text("Continue")
      break
    case "Continue":
      // move on to the next scenario
      submit_button.before(`<hr style="width: 80%">`)
      scenario_num++
      nextScenario()
      submit_button.text("Submit")
      // enable button after a delay
      setTimeout(function() { submit_button.prop("disabled", false) }, 1000)
      break
  }
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
  
  $("progress").val(scenario_num/scenarios.length)
  let scenario = scenarios[scenario_num]
  let married = scenario["marital_status"] == "married"
  let len_a = 100, len_b = 100
  if (married) {
    let a_over_b = (scenario["life_expectancy_a"] - scenario["current_age_a"])/(scenario["life_expectancy_b"] - scenario["current_age_b"])
    len_a = 100*Math.min(1, a_over_b)
    len_b = 100*Math.min(1, 1/a_over_b)
  }
  $("#submit").before(`
    <table>
      <tr>
        <th scope="col" style="border: none"></th>
        <th scope="col">PIA</th>
        <th scope="col">Lifespan<br><span style="font-size:14px">(Select filing age between 62 and 70)</span></th>
        <th scope="col">Optimal<br>Age</th>
        <th scope="col">Error</th>
        ` + (section == "testing" ? `<th scope="col">Bonus<br>Earned</th>` : ``) + `
      </tr>
    </table>
  `)
  $("table tr:last").after(`
    <tr>
      <th scope="row">` + (married ? `Spouse A` : `Individual`) + `</th>
      <td>$` + scenario["pia_a"] + `</td>
      <td class="slider-cell">
        <output style="width: ` + len_a + `%">66</output>
        <input type="range" min="` + scenario["current_age_a"] + `" max="` + scenario["life_expectancy_a"] + `" value="66" list="markers_a` + scenario_num + `" class="slider spouse_a" style="width: ` + len_a + `%">
        <datalist id="markers_a` + scenario_num + `" style="width: ` + len_a + `%">
          <option value="` + scenario["current_age_a"] + `" label="` + scenario["current_age_a"] + `"></option>
          <option value="62"></option>
          <option value="70"></option>
          <option value="` + scenario["life_expectancy_a"] + `" label="` + scenario["life_expectancy_a"] + `"></option>
        </datalist>
      </td>
      <td class="optimal_a"></td>
      <td class="error_a"></td>
      ` + (section == "testing" ? `<td class="bonus_a"></td>` : ``) + `
    </tr>
  `)
  if (married) {
    $("table tr:last").after(`
    <tr>
      <th scope="row">Spouse B</th>
      <td>$` + scenario["pia_b"] + `</td>
      <td class="slider-cell">
        <output style="width: ` + len_b + `%">66</output>
        <input type="range" min="` + scenario["current_age_b"] + `" max="` + scenario["life_expectancy_b"] + `" value="66" list="markers_b` + scenario_num + `" class="slider spouse_b" style="width: ` + len_b + `%">
        <datalist id="markers_b` + scenario_num + `" style="width: ` + len_b + `%">
          <option value="` + scenario["current_age_b"] + `" label="` + scenario["current_age_b"] + `"></option>
          <option value="62"></option>
          <option value="70"></option>
          <option value="` + scenario["life_expectancy_b"] + `" label="` + scenario["life_expectancy_b"] + `"></option>
        </datalist>
      </td>
      <td class="optimal_b"></td>
      <td class="error_b"></td>
      ` + (section == "testing" ? `<td class="bonus_b"></td>` : ``) + `
    </tr>
  `)
  }
}

// undeclared vars
let cur_message, scenarios
// general vars
const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay))
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
const chat_display = () => $(".msg-inbox").last()
let dots = '●'
function accuracyStatement(s, o) {
  if (s - o < -4) return "too low. They should file much later."
  if (s - o < 0) return "close! They should file slightly later."
  if (s - o == 0) return "exactly right!"
  if (s - o < 4) return "close! They should file slightly earlier."
  return "too high. They should file much earlier."
}
class explanation_tags {
  constructor(scenario, selection) {
    this.lifespanA = Number(scenario["life_expectancy_a"])
    this.PIAA = Number(scenario["pia_a"])
    this.nameA = "Spouse A"
    this.optimalAgeA = scenario["optimal_age_a"]
    this.fewestYearsA = this.lifespanA - 70
    this.mostYearsA = this.lifespanA - 62
    this.accuracyStatementA = accuracyStatement(Number(selection["selection_a"]), this.optimalAgeA)
    if (scenario["marital_status"] == "married") {
      this.lifespanB = Number(scenario["life_expectancy_b"])
      this.PIAB = Number(scenario["pia_b"])
      this.nameB = "Spouse B"
      this.optimalAgeB = scenario["optimal_age_b"]
      this.fewestYearsB = this.lifespanB - 70
      this.mostYearsB = this.lifespanB - 62
      this.accuracyStatementB = accuracyStatement(Number(selection["selection_b"]), this.optimalAgeB)
      this.fewestYearsMin = Math.min(this.fewestYearsA, this.fewestYearsB)
      this.fewestYearsMax = Math.max(this.fewestYearsA, this.fewestYearsB)
      this.mostYearsMin = Math.min(this.mostYearsA, this.mostYearsB)
      this.mostYearsMax = Math.max(this.mostYearsA, this.mostYearsB)
      this.lowLifespanSpouse = this.lifespanA <= this.lifespanB ? this.nameA : this.nameB
      this.highLifespanSpouse = this.lifespanA > this.lifespanB ? this.nameA : this.nameB
      this.lowPIASpouse = this.PIAA <= this.PIAB ? this.nameA : this.nameB
      this.highPIASpouse = this.PIAA > this.PIAB ? this.nameA : this.nameB
    }
  }

  replace_in(explanation) {
    for (let tag in this) {
      explanation = explanation.replace("{"+tag+"}", this[tag])
    }
    return explanation
  }
}

// get section's scenarios
$.ajax({
  method: "POST",
  url: "/get_scenarios/",
  contentType: "application/json",
  success: function(data) {
    scenarios = data
    if (section == "practice") {
      $("nav p").text("Practice Section")
    } else {
      $("nav p").text("Testing Section")
    }
    
    nextScenario()
    timer.start()
  },
  error: function(err) {
    console.log(err)
  }
})
