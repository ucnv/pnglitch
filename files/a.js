$(function() {
  var lazyLoad = function(evt) {
    $('.full img, .catalog img').each(function(i) {
      var img = $(this);
      if (img.attr('src') != 'files/blank.png') return;
      if (img.position().top > $(window).scrollTop() + $(window).height() * 2) return;
      img.attr('src', img.data('src'));
    });
  };
  $(window).scroll(lazyLoad);
});
