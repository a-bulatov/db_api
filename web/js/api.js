var editor = null;
window.onload = function () {
    editor = CodeMirror(document.getElementById("code"), {
        lineNumbers: true,
        tabSize: 4,
        value: "{}",
        mode: "javascript",
        theme: "idea",
        matchBrackets: true,
    });
    fetch("/api", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ method: "help" }),
    })
        .then((response) => response.json())
        .then((result) => {
            let sel = document.getElementById("method");
            for (let x of result.result) {
                const option = document.createElement("option");
                option.textContent = option.value = x;
                sel.append(option);
            }
        })
        .catch((error) => console.error("Error:", error));
};

function getParams() {
    let params = editor.getValue().trim();
    try {
        if (params.length == 0) params = "{}";
        return JSON.parse(params);
    } catch (e) {
        fetch("/api", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                method: "json_syntax_check",
                params: {
                    text_b64: btoa(unescape(encodeURIComponent(params))),
                },
            }),
        })
            .then((response) => response.json())
            .then((result) => {
                let out = document.getElementById("finite-output");
                out.innerHTML = `<pre>${result.result.message}</pre>`;
            })
            .catch((error) => console.error("Error:", error));
        throw new Error("Ошибка в JSON");
    }
}

function run() {
    let sel = document.getElementById("method");
    let method = sel.value;
    let params = getParams();
    const time = performance.now();
    fetch("/api", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ method: method, params: params }),
    })
        .then((response) => response.json())
        .then((result) => {
            let out = document.getElementById("finite-output");
            out.innerHTML = `<pre>${JSON.stringify(result, null, 4).replaceAll("\\n", "\n").replaceAll('\"', '"')}</pre>`;
            out = document.getElementById("timing");
            out.innerHTML = (Math.round(performance.now() - time) / 1000)
                .toString()
                .concat(" сек.");
        })
        .catch((error) => console.error("Error:", error));
}

function help() {
    let sel = document.getElementById("method");
    let method = sel.value;
    fetch("/api", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ method: "help", params: { method: method } }),
    })
        .then((response) => response.json())
        .then((result) => {
            let out = document.getElementById("finite-output");
            out.innerHTML = `<pre>${result.result}</pre>`;
        })
        .catch((error) => console.error("Error:", error));
}

function format() {
    let params = getParams();
    editor.setValue(JSON.stringify(params, null, 4));
}
