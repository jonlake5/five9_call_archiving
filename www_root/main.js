const uriBase = 'https://qg2omq2odh.execute-api.us-east-1.amazonaws.com/prod/'
const uriEndpoint = uriBase + 'query';
const agentUriEndpoint = uriBase + 'agents';

// $('#search-button').on('click', function(event) {
//     $(this).disabled = true;
//     event.preventDefault();
//     console.log("form submitted!")  // sanity check
//     clearResults();
//     queryDatabase();
//     // document.getElementById("search-button").disabled = false;
//     return false;
// });

$('#input-form').on('submit', function(event) {
    freeze_button();
    event.preventDefault();
    

    console.log("form submitted!")  // sanity check
    clearResults();
    queryDatabase();
    
    return false;
});

$('#from_date').on('change', function() {
    console.log('Is date valid? ', validate_date());
});


$('#to_date').on('change', function() {
    console.log('Is date valid? ', validate_date());
});

let select_agent_name = document.getElementById("agent_name");

getAgents();

async function getAgents() {
    freeze_button();
    let return_data = {};
    const response = await fetch(agentUriEndpoint)
        .then(
            response => response.json()
        )
        .then(
            json => return_data = json
        )
        .finally(() => {
            unfreeze_button();
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

function clearResults() {
    let tbl = document.getElementById("results-table")
    if (tbl) {
        // tbl.parentElement.style.backgroundColor = "#"
        tbl.parentNode.removeChild(tbl);
    }
}

async function queryDatabase() {  
    let to_date = getValueByElement('to_date') || new Date().toISOString().split('T')[0];
    let from_date = getValueByElement('from_date') || new Date('1970-01-01').toISOString().split('T')[0];
    let data = {
        'agent_name': getValueByElement('agent_name'),
        'consumer_number': getValueByElement('consumer_number'),
        'from_date': from_date,
        'to_date': to_date
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
        unfreeze_button();
        return false;
        }
    )
}

function displayResults(results) {
    //Create a table to display the results
    const table_parent = document.getElementById("results-table-container");
    const headers = ['Date','Agent','Consumer Number','Download'];
    let tbl = document.createElement('table');
    tbl.setAttribute("id","results-table");
    //Add Header
    let header = tbl.createTHead();
    let header_row = header.insertRow(0);
    for (index in headers) {
        addCellText(header_row,index,headers[index]);
    };
    let tbody = tbl.createTBody();
    for (index in results) {
        const field_mapping = {
            "date": 0,
            "agent": 1,
            "consumer_number": 2,
            "url": 3
        }

        let tr = tbody.insertRow(index);
        let row = results[index];
        console.log('here is the row', row)
        let [url,date,agent_name,consumer_number] = row
        console.log(`The url is ${url}, the date is ${date} agent is ${agent_name}`)
        urlImage = createLink(url)
        addCellText(tr,field_mapping['date'],date)
        addCellText(tr,field_mapping['agent'],agent_name)
        addCellText(tr,field_mapping['consumer_number'],consumer_number)
        addCellLink(tr,field_mapping['url'],urlImage)
    }
    table_parent.appendChild(tbl);
}

function addCellText(row,index,value) {
    let td = row.insertCell(index)
    td.innerHTML = value
}

function addCellLink(row,index,value) {
    let td = row.insertCell(index)
    td.appendChild(value)
}

function createLink(url) {
    let img = document.createElement("img")
    img.width = 25
    img.height = 25
    img.src = 'file_download.png';
    let a = document.createElement("a")
    a.href = url
    a.target = "_blank"
    a.appendChild(img)
    return a

}
function getValueByElement(element) {
    return document.getElementById(element).value
}

// let searchButton = document.getElementById("search");

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

function validate_date() {
    let from_date =  document.getElementById("from_date").value;
    let to_date = document.getElementById("to_date").value;
    let today = new Date().toISOString().split('T')[0];
    console.log("From date", from_date);
    console.log("To Date", to_date);
    if (from_date > today) {
        freeze_button();
        return false;
    } else if (! from_date || ! to_date) {
        console.log("One date is not specified")
        unfreeze_button();
        return true;
    } else if (from_date > to_date) {
        console.log("From date is after to date");
        freeze_button();
        return false;
    } else {
        console.log("Date validation default true");
        unfreeze_button();
        return true;
    }
}

function freeze_button() {
    document.getElementById("search-button").disabled = true;
}

function unfreeze_button() {
    document.getElementById("search-button").disabled = false;
}