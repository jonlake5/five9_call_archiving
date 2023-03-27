const uriBase = 'https://qg2omq2odh.execute-api.us-east-1.amazonaws.com/prod/'
const uriEndpoint = uriBase + 'query';
const agentUriEndpoint = uriBase + 'agents';
const getUrlUriEndoint = uriBase + 'get_url';
const authUrl = 'https://auth.jlake.aws.sentinel.com/login?client_id=fpmf66abi4079ea7m5ecbl5fo&response_type=token&scope=email+openid&redirect_uri=https%3A%2F%2Fapp.jlake.aws.sentinel.com'

//Verify this person is authenticated
const id_token = idToken(window.location.href);
if (! id_token) {
    console.log("Not seeing id_token in params")
    window.location.replace(authUrl);
} else {
    getAgents();
}

$(document).on("click", ".download-button", function(){
    // Do something with `$(this)`.
    console.log(this)
    getPreSignedUrl(this.value)
  });

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

function idToken(url) {
    let queryString = url.split('#')[1]
    if (queryString) {
        params = queryString.split('&')
        for (index in params) {
            let [key,value] = params[index].split('=')
            if (key === 'id_token') {
                console.log(value)
                return value;
            }
            return false;
        }
    }
}

async function getAgents() {
    freeze_button();
    const response = await fetch(agentUriEndpoint, {
		method: 'GET',
		headers: {
			'Authorization': id_token
		},
	}
        )
        .then(
            response => {
                console.log(response);
                if (response['status'] === 200) {
                    return response.json();
                } else {
                    console.log("Houston we have a problem")
                    throw new Error("Unsuccessful response. Redirecting to login.")
                }
            }
        )
        .then(
            json => {
                listAgents(json['agents'])
            }
        )
        .catch(
            error => {
                console.log(error)
                window.location.replace(authUrl);
            }
        )
        .finally(() => {
            unfreeze_button();
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
        headers: {
            'Content-Type': 'application/json',
            'AUthorization': id_token
        }, 
        body: JSON.stringify(data)
    })
    .then( 
        response => {
        if (response['status'] === 200) {
            return response.json();
        } else {
            console.log("Houston we have a problem")
            throw new Error("Unsuccessful response. Redirecting to login.")
        }

        }
    )
    .then(
        json => {
            console.log(json)
            displayResults(json['results'])
        }
    )
    .catch(
        error => {
            console.log(error)
            window.location.replace(authUrl);
        }
    )
    .finally(() => {
        unfreeze_button();
        return false;
        }
    )
}

function displayResults(results) {
    const table_parent = document.getElementById("results-table-container");
    const headers = ['Date','Time','Agent','Consumer Number','Download'];
    if (results.length == 0) {
        alert("No items return for this search");
    }
    //Create a table to display the results
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
        let tr = tbody.insertRow(index);
        let row = results[index];
        console.log('here is the row', row)
        let [url,date,agent_name,consumer_number,time] = row
        console.log(`The url is ${url}, the date is ${date} agent is ${agent_name}`)
        urlImage = createLink(url)
        cell_index = 0
        addCellText(tr,cell_index++,date)
        addCellText(tr,cell_index++,time)
        addCellText(tr,cell_index++,agent_name)
        addCellText(tr,cell_index++,consumer_number)
        addCellLink(tr,cell_index++,urlImage)
    }
    table_parent.appendChild(tbl);
}

async function getPreSignedUrl(object_name) {  
    let data = {
        'object_name': object_name
    };
    console.log(`Trying to download ${data} by generating a presigned URL`);

    let response = await fetch(getUrlUriEndoint, {
        method: "POST",
        headers: {
            'Content-Type': 'application/json',
            'AUthorization': id_token
        }, 
        body: JSON.stringify(data)
    })
    .then( 
        response => { 
            if (response['status'] === 200) {
            return response.text() 
        } else {
            throw new Error("Unsuccessful response. Redirecting to login.")
        }
    })
    .then(
        json => {
            console.log(`This is the file we would pass ${json}`)
            download(json)
        }
    )
    .catch( error => {
        console.log(error)
        window.location.replace(authUrl);
    }
        
        )
    .finally(() => {
        return false;
        }
    )
}

function download(dataurl) {
    const link = document.createElement("a");
    link.href = dataurl;
    link.target = "_blank";
    link.click();
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
    let btn = document.createElement("button")
    btn.value = url
    btn.setAttribute("class","download-button")
    btn.appendChild(img)
    return btn
}

function getValueByElement(element) {
    return document.getElementById(element).value
}

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



