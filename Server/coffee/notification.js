// Generated by CoffeeScript 1.8.0
(function() {
  this.showNotification = function(mes, type) {
    var html, jqObj;
    html = "<div class='alert alert-" + type + "' role='alert'> <button type='button' class='close' data-dismiss='alert'> <span aria-hidden='true'>x</span> </button> " + mes + " </div>";
    jqObj = $(html);
    $('#manage-body-main').prepend(jqObj);
    return setTimeout(function() {
      return jqObj.alert('close');
    }, 5000);
  };

}).call(this);

//# sourceMappingURL=notification.js.map