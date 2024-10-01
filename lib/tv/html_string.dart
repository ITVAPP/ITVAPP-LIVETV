import '../generated/l10n.dart';

String getHtmlString(String ipAddress) => '''
<!DOCTYPE html>
<html lang="zh_CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${S.current.appName}</title>
    <style>
        body {
            padding: 40px;
            background-color: #f0f0f0;
            background-image: url('https://cdn.itvapp.net/itvapp_live_tv/idiom_bg.jpg');
            background-size: cover;
            background-position: center;
            background-repeat: no-repeat;
            height: 100vh;
            font-size: 28px; /* 调整字体大小，适应TV */
        }
        h2 {
            color: #333;
            font-size: 36px; /* 提高标题字体大小 */
        }
        textarea {
            width: 100%;
            min-height: 150px; /* 提高文本框高度 */
            padding: 20px;
            font-size: 24px; /* 提高输入区域字体大小 */
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
            padding: 20px 40px; /* 增加按钮尺寸 */
            background-color: #007bff;
            color: white;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 28px; /* 提高按钮字体大小 */
            transition: background-color 0.3s ease;
            outline: none;
        }
        button:hover,
        button:focus {
            background-color: #0056b3;
            outline: 3px solid #fff; /* 为焦点按钮增加高亮边框 */
        }
        button:disabled {
            background-color: #aaa;
        }
    </style>
<script>
    // 自动调整文本框高度
    function autoResize(element) {
        element.style.height = "auto";
        element.style.height = (element.scrollHeight) + "px";
    }

    // 发送POST请求到指定IP地址
    function sendPostRequest() {
        var userInput = document.getElementById("userInput").value;

        // 检查用户输入是否为空
        if (!userInput.trim()) {
            alert("${S.current.addFiledHintText}");
            return;
        }

        var url = "$ipAddress";  // 使用传入的IP地址
        var data = { url: userInput };

        // 提交按钮禁用，避免重复提交
        var submitButton = document.querySelector("button");
        submitButton.disabled = true;
        submitButton.textContent = "${S.current.downloading}";

        fetch(url, {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify(data)
        })
        .then(response => {
            submitButton.disabled = false;
            submitButton.textContent = "${S.current.dataSourceContent}";

            // 检查响应状态
            if (!response.ok) {
                throw new Error('${S.current.netTimeOut}');
            }
            return response.json();
        })
        .then(data => {
            alert(data.message);
        })
        .catch(error => {
            // 显示错误信息
            alert("${S.current.filterError}: " + error.message);
        });
    }
</script>
</head>
<body>
    <h2>${S.current.addDataSource}</h2>
    <!-- 增加 tabindex 使文本框和按钮可以通过遥控器聚焦 -->
    <textarea id="userInput" placeholder="${S.current.addFiledHintText}" oninput="autoResize(this)" tabindex="1"></textarea>
    <br><br>
    <button onclick="sendPostRequest()" tabindex="2">${S.current.dialogConfirm}</button>
</body>
</html>
''';
