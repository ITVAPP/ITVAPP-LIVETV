(function() {
  console.log("查找搜索表单元素");
  
  const form = document.getElementById('form1'); // 查找表单
  const searchInput = document.getElementById('search'); // 查找输入框
  const submitButton = document.querySelector('input[name="Submit"]'); // 查找提交按钮
  
  if (!searchInput || !form) {
    console.log("未找到表单元素");
    console.log("表单数量: " + document.forms.length);
    for(let i = 0; i < document.forms.length; i++) {
      console.log("表单 #" + i + " ID: " + document.forms[i].id);
    }
    
    const inputs = document.querySelectorAll('input');
    console.log("输入框数量: " + inputs.length);
    for(let i = 0; i < inputs.length; i++) {
      console.log("输入 #" + i + " ID: " + inputs[i].id + ", Name: " + inputs[i].name);
    }
    
    return false;
  }
  
  searchInput.value = "{{SEARCH_KEYWORD}}"; // 填写关键词
  console.log("填写关键词: " + searchInput.value);
  
  if (submitButton) {
    console.log("点击提交按钮");
    submitButton.click();
    return true;
  } else {
    console.log("未找到提交按钮，尝试其他方法");
    
    const otherSubmitButton = form.querySelector('input[type="submit"]'); // 查找其他提交按钮
    if (otherSubmitButton) {
      console.log("找到submit按钮，点击");
      otherSubmitButton.click();
      return true;
    } else {
      console.log("直接提交表单");
      form.submit();
      return true;
    }
  }
})();
