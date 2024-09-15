String getHtmlString(String ipAddress) => '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ITVAPP LIVETV</title>
    <style>
        body {
            padding: 40px;
            background-color: #f0f0f0;
            background-image: url('https://cdn.itvapp.net/itvapp_live_tv/idiom_bg.jpg');
            background-size: cover;
            background-position: center;
            background-repeat: no-repeat;
            height: 100vh;
            font-size: 28px; /* Adjust font size for TV */
        }
        h2 {
            color: #333;
            font-size: 36px; /* Increase title font size */
        }
        textarea {
            width: 100%;
            min-height: 150px; /* Increase text area height */
            padding: 20px;
            font-size: 24px; /* Increase input area font size */
            border: 2px solid #ccc;
            border-radius: 8px;
            box-sizing: border-box;
            resize: none;
        }
        textarea:focus {
            border-color: #007bff;
            outline: none;
        }
        button {
            padding: 20px 40px; /* Increase button size */
            background-color: #007bff;
            color: white;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 28px; /* Increase button font size */
            transition: background-color 0.3s ease;
            outline: none;
        }
        button:hover,
        button:focus {
            background-color: #0056b3;
            outline: 3px solid #fff; /* Add highlight border for focused button */
        }
        button:disabled {
            background-color: #aaa;
        }
    </style>
<script>
    function autoResize(element) {
        element.style.height = "auto";
        element.style.height = (element.scrollHeight) + "px";
    }

    function sendPostRequest() {
        var userInput = document.getElementById("userInput").value;
        if (!userInput.trim()) {
            alert("Subscription source cannot be empty!");
            return;
        }

        var url = "$ipAddress";
        var data = { url: userInput };

        var submitButton = document.querySelector("button");
        submitButton.disabled = true;
        submitButton.textContent = "Sending...";

        fetch(url, {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify(data)
        })
        .then(response => {
            submitButton.disabled = false;
            submitButton.textContent = "Submit Now";
            if (!response.ok) {
                throw new Error('Network response was not ok');
            }
            return response.json();
        })
        .then(data => {
            alert(data.message);
        })
        .catch(error => {
            alert("Request failed: " + error.message);
        });
    }
</script>
</head>
<body>
    <h2>Add Subscription Source</h2>
    <textarea id="userInput" placeholder="Enter subscription source" oninput="autoResize(this)" tabindex="1"></textarea>
    <br><br>
    <button onclick="sendPostRequest()" tabindex="2">Submit Now</button>
</body>
</html>
''';
