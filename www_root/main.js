const uriBase = 'https://qg2omq2odh.execute-api.us-east-1.amazonaws.com/prod/'
const uriEndpoint = uriBase + 'query';
const agentUriEndpoint = uriBase + 'agents';

$('#input-form').on('submit', function(event) {
    event.preventDefault();
    console.log("form submitted!")  // sanity check
    queryDatabase();
    return false;
});

let all_agents = getAgents();
console.log('Did we get here?')




async function getAgents() {
    let return_data = {};
    const response = await fetch(agentUriEndpoint)
        .then(
            response => response.json()
            )
        .then(
            json => return_data = json
        ).finally(() => {
            listAgents(return_data['agents']);
        })
}






function listAgents(agents) {
    console.log("Adding options for all agents");
    console.log(agents);
    for(index in agents)
    {

        let agent_id = agents[index]['agent_id'];
        let agent_name = agents[index]['agent_name'];
        var opt = document.createElement("option");
        opt.value = agent_id;
        opt.innerHTML = agent_name; // whatever property it has
          // then append it to the select element
        selectItem = document.getElementById('agent_name')
        selectItem.appendChild(opt);
    }
}


async function queryDatabase() {
    // let return_data = {};

    let data = {
        'agent_name': getValueByElement('agent_name'),
        'consumer_number': getValueByElement('consumer_number'),
        'from_date': getValueByElement('from_date'),
        'to_date': getValueByElement('to_date')
    };
    console.log(data);

    let response = await fetch(uriEndpoint, {
        method: "POST",
        headers: {'Content-Type': 'application/json'}, 
        body: JSON.stringify(data)
    })
    .then( 
        response => response.json()
    )
    .then(
        json => {
            console.log(json)
            displayResults(json['results'])
        }
    )
    .finally(() => {
        return false;
        }
    )
}

function displayResults(results) {
    //Create a table to display the results
    const body = document.body,
        tbl = document.createElement('table');

    for (index in results) {
        let tr = tbl.insertRow(index);
        let row = results[index];
        console.log('here is the row', row)
        // let [row_id,url,date,agent_id,consumer_number] = row
        for (cell_index in row) {
            let td = tr.insertCell(cell_index)
            td.innerHTML = row[cell_index]
        }
    }
    body.appendChild(tbl);
}


// async function queryDatabase() {
//     let return_data = {};

//     let data = {
//         'agent_name': getValueByElement('agent_name'),
//         'consumer_number': getValueByElement('consumer_number'),
//         'from_date': getValueByElement('from_date'),
//         'to_date': getValueByElement('to_date')
//     };
//     console.log(data);
//     let response = await fetch(uriEndpoint, {
//         method: "POST",
//         headers: {'Content-Type': 'application/json'}, 
//         body: JSON.stringify(data)
//     });
//     if (response.status === 200) {
//         let return_data = await response.json();
//         console.log("Here is the data\n" + return_data);
//     }
//     console.log(return_data);
//     return false;
// }

function getValueByElement(element) {
    return document.getElementById(element).value
}

let searchButton = document.getElementById("search");

function submit() {
    console.log("Hello");
    let from_date = document.getElementById("from_date").value;
    let to_date = document.getElementById("to_date").value;
    let consumer_number = document.getElementById("consumer_number").value;
    let agent_name = document.getElementById("agent_name").value;
    console.log(`from_date is ${from_date}`);
    console.log(`to_date is ${to_date}`);
    console.log(`consumer_number is ${consumer_number}`);
    console.log(`agent_name is ${agent_name}`);
}

