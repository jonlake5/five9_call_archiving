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

