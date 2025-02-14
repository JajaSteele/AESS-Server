var raw_data = []
var time_to_diff = new Map()

function httpGetAsync(theUrl, payload, callback)
{
    console.log("New request: " + theUrl + " " + payload)
    var xmlHttp = new XMLHttpRequest();
    xmlHttp.onreadystatechange = function() { 
        if (xmlHttp.readyState == 4 && xmlHttp.status == 200)
            callback(xmlHttp.responseText);
    }
    xmlHttp.open("POST", theUrl, true); // true for asynchronous 
    xmlHttp.send(payload);
}

document.getElementById("button_test_display").addEventListener("click", function() {
    const time_column = document.getElementById("time_column")
    const display_column = document.getElementById("display_column")
    
    for (let step = 0; step < 24; step++) {
        const new_element = document.createElement("button")
        new_element.className = "time_button"
        time_column.appendChild(new_element)
    }

    for (let step = 0; step < 60; step++) {
        const new_element = document.createElement("button")
        if (step%2 == 0) {
            new_element.className = "display_add"
        } else {
            new_element.className = "display_remove"
        }
        display_column.appendChild(new_element)
    }
})

function createDisplayElement(count, name, players) {
    const new_element = document.createElement("button")
    if (count < 0) {
        new_element.className = "display_remove"
    } else {
        new_element.className = "display_add"
    }
    const count_box = document.createElement("div")
    count_box.className = "display_sub_count"
    count_box.innerText = count

    const name_box = document.createElement("div")
    name_box.className = "display_sub_name"
    name_box.innerText = name

    const player_box = document.createElement("div")
    player_box.className = "display_sub_players"
    player_box.innerText = players.join(", ")


    new_element.appendChild(count_box)
    new_element.appendChild(name_box)
    new_element.appendChild(player_box)
    return new_element
}

function createTimeElement(line1, line2, line3) {
    const new_element = document.createElement("button")

    const line_box1 = document.createElement("div")
    line_box1.className = "time_sub"
    line_box1.innerText = line1

    const line_box2 = document.createElement("div")
    line_box2.className = "time_sub"
    line_box2.innerText = line2

    const line_box3 = document.createElement("div")
    line_box3.className = "time_sub"
    line_box3.innerText = line3


    new_element.appendChild(line_box1)
    new_element.appendChild(line_box2)
    new_element.appendChild(line_box3)
    return new_element
}

document.getElementById("button_fetch_history").addEventListener("click", function() {
    const url_box = document.getElementById("input_url")
    const key_box = document.getElementById("input_key")
    const urlServer = new URL(url_box.value);
    httpGetAsync(urlServer, JSON.stringify({type:"request_history", key:key_box.value}), function(body) {
        const time_column = document.getElementById("time_column")
        console.log(body)
        raw_data = JSON.parse(body)

        const display_mode = document.getElementById("dropdown_display_mode").value

        time_column.innerHTML = ""
        if (display_mode == "min") {
            raw_data.data.forEach(obj => {
                var d = new Date(0);
                d.setUTCMilliseconds(obj.time)
                const new_element = createTimeElement(d.toLocaleString("fr-FR"), "Nearby: " + Object.keys(obj.nearby_players).length, "")
                new_element.className = "time_button"

                new_element.addEventListener("click", function() {
                    const data = obj
                    const display_column = document.getElementById("display_column")
                    const info_box = document.getElementById("info_box")
                    var display_array = []
                    display_column.innerHTML = ""
                    console.log("Type: " + typeof(data.diffs.item))
                    Object.keys(data.diffs.item).forEach((name) => {
                        item_diff = data.diffs.item[name]
                        display_array.push({name:name, diff:item_diff})
                    })

                    display_array.sort(function(a,b) {
                        return a.diff - b.diff
                    })

                    display_array.forEach(data => {
                        const new_element = createDisplayElement(data.diff, data.name, [])
                        display_column.appendChild(new_element)
                    })

                    var player_array = []
                    Object.keys(data.nearby_players).forEach((name) => {
                        player_array.push(name)
                    })

                    if (player_array.length == 0) {
                        info_box.innerText = "No players nearby"
                    } else {
                        info_box.innerText = player_array.join(", ")
                    }
                })
                time_column.appendChild(new_element)
            })
        } else if (display_mode == "hour") {
            var merged_hour_data = []
            var merged_buffer = new Map()
            var time = null
            var old_time = 0
            var new_time = 0
            var big_time = 0
            var players = new Map()
            raw_data.data.forEach((obj, ind) => { // For each minute data
                if (!time) {
                    time = obj.time
                }
                old_time = new_time
                new_time = obj.time / 1000 % (60*60)
                if (big_time < obj.time) {
                    big_time = obj.time
                }
                Object.keys(obj.nearby_players).forEach((name) => { //For each player name, set them to true (Map prevents duplicates)
                    players.set(name, true)
                })
                Object.keys(obj.diffs).forEach((diff_type) => { // For each type of diff
                    diff_data = obj.diffs[diff_type]
                    if (!(merged_buffer[diff_type])) { //Creates a new object if the diff type doesn't exist yet in the buffer
                        merged_buffer[diff_type] = {}
                    }
                    Object.keys(diff_data).forEach((name) => { //For each item inside this diff type
                        diff = diff_data[name]
                        if (!(merged_buffer[diff_type][name])) {
                            merged_buffer[diff_type][name] = diff
                        } else {
                            merged_buffer[diff_type][name] = merged_buffer[diff_type][name] + diff
                        }
                    })
                })
                if (old_time > new_time || ind+1 == raw_data.data.length) {
                    var players_array = []
                    players.forEach((val, name) => { // For each player name, add them to the array
                        players_array.push(name)
                    })
                    players = new Map()
                    merged_hour_data.push({data:merged_buffer, time:time, time_max:big_time, players:players_array})
                    merged_buffer = new Map()
                    time = null
                    big_time = 0
                }
            })

            merged_hour_data.forEach(obj => {
                var d = new Date(0);
                d.setUTCMilliseconds(obj.time_max)
                const new_element = createTimeElement(d.toLocaleString("fr-FR"), "Nearby: " + obj.players.length, "")
                console.log("Adding button: " + d.toLocaleString("fr-FR"))
                new_element.className = "time_button"
                new_element.addEventListener("click", function() {
                    const data = obj
                    const display_column = document.getElementById("display_column")
                    const info_box = document.getElementById("info_box")
                    var display_array = []
                    display_column.innerHTML = ""
                    console.log("Type: " + typeof(data.data.item))
                    Object.keys(data.data.item).forEach((name) => {
                        item_diff = data.data.item[name]
                        display_array.push({name:name, diff:item_diff})
                    })

                    display_array.sort(function(a,b) {
                        return a.diff - b.diff
                    })

                    display_array.forEach(data => {
                        const new_element = createDisplayElement(data.diff, data.name, [])
                        display_column.appendChild(new_element)
                    })

                    if (data.players.length == 0) {
                        info_box.innerText = "No players nearby"
                    } else {
                        info_box.innerText = data.players.join(", ")
                    }
                })
                time_column.appendChild(new_element)
            })

            console.log(JSON.stringify(merged_hour_data, null, 2))
        }
    })
})