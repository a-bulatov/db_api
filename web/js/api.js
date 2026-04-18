var editor = null;
window.onload = function() {
    editor = CodeMirror(document.getElementById("code"), {
      lineNumbers: true,
      tabSize: 4,
      value: '{}',
      mode: 'javascript',
      theme: 'idea',
      matchBrackets:true
    });
    fetch('/api', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({"method": "help"})
    }).then(response => response.json())
    .then(result => {
          let sel = document.getElementById("method");
          for (let x of result.result) {
                const option = document.createElement('option');
                option.textContent = option.value = x;
                sel.append(option);
          }
    })
    .catch(error => console.error('Error:', error));
};

function run(){
    let sel = document.getElementById("method");
    let method = sel.value;
    let params = editor.getValue().trim();
    if(params.length==0) params='{}';
    fetch('/api', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({"method": method, "params":  JSON.parse(params)})
    }).then(response => response.json())
    .then(result => {
          let out = document.getElementById("finite-output");
          out.innerHTML = `<pre>${JSON.stringify(result, null, 4)}</pre>`;
    })
    .catch(error => console.error('Error:', error));
};

function help(){
    let sel = document.getElementById("method");
    let method = sel.value;
    fetch('/api', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({"method": "help", "params":{"method":method}})
    }).then(response => response.json())
    .then(result => {
          let out = document.getElementById("finite-output");
          out.innerHTML = `<pre>${result.result}</pre>`;
    })
    .catch(error => console.error('Error:', error));
};

function format(){
   let params = editor.getValue();
   editor.setValue(JSON.stringify(JSON.parse(editor.getValue()),null , 4));
};