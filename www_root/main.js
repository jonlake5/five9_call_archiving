const uriEndpoint = 'https://jodgus5ns1.execute-api.us-east-1.amazonaws.com/prod';

$('#input-form').on('submit', function(event) {
    event.preventDefault();
    console.log("form submitted!")  // sanity check
    queryDatabase();
    return false;

});


async function queryDatabase() {
    let return_data = {};

    let data = {
        'agent_name': getValueByElement('agent_name'),
        'consumer_number': getValueByElement('consumer_number'),
        'from_date': getValueByElement('from_date'),
        'to_date': getValueByElement('to_date')
    };

    let response = await fetch(uriEndpoint, {
        method: "POST",
        headers: {'Content-Type': 'application/json'}, 
        body: JSON.stringify(data)
    });
    if (response.status === 200) {
        let data = await response.json();
        console.log("Here is the data\n" + data);
    }
    console.log(return_data);
    updateConversation(return_data,user_visible);
    
    return false;

}

function getValueByElement(element) {

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

