// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// the compiled file.
//
// WARNING: THE FIRST BLANK LINE MARKS THE END OF WHAT'S TO BE PROCESSED, ANY BLANK LINE SHOULD
// GO AFTER THE REQUIRES BELOW.
//
//= require jquery
//= require easing
//= require mousewheel
//= require jquery-ui
//= require jquery_ujs
//= require jqcloud-0.2.10
//= require jquery.tipsy
//= require jquery.noty
//= require jquery.simplemodal
//= require rhinoslider-1.04
//= require jquery.tokeninput
//= require jquery.joyride-1.0.3

Array.prototype.unique = function () {
    var o = {}, i, l = this.length, r = [];
    for (i = 0; i < l; i += 1) o[this[i]] = this[i];
    for (i in o) r.push(o[i]);
    return r;
};


$(function () {
    $.notyConf = {
        layout:'topRight',
        timeout:1000
    };

    $.getCredible = {};

    $.getCredible.displayNotification = function (type, text) {
        noty({
            text:text,
            type:type,
            timeout:$.notyConf.timeout,
            layout:$.notyConf.layout,
            onClose:function () {
            }
        });
    };

    $.getCredible.init = function () {
        $.getCredible.tagCloudPath = null;
        $.getCredible.tagCloudLoader = $("#tag-cloud-loader");
        $.getCredible.tagCloud = $("#tag-cloud");

        var tagNamesTextField = $("#tag_names");
        if (tagNamesTextField.length > 0) {
            tagNamesTextField.tokenInput("/tags/search", {
                method:'POST',
                queryParam:'term',
                propertyToSearch:'term',
                tokenValue:'term',
                crossDomain:false,
                theme:"facebook",
                hintText:'e.g. web design, leadership (comma separated)',
                minChars:2
            });
        }

        $("#tag-cloud").delegate(".remove .icon", "click", function () {
            var word = $(this).parent();
            noty({
                text:'Are you sure you want to delete this tag?',
                layout:'center',
                type:'alert',
                buttons:[
                    {type:'button green', text:'Ok', click:function () {
                        if ($.getCredible.tagCloud.data('can-delete')) {
                            $.post($.getCredible.tagCloudPath + '/' + word.data('user-tag-id'), { _method:'delete' }, function (data) {
                                $.getCredible.renderTagCloud(data);
                            });
                        }
                    } },
                    {type:'button orange', text:'Cancel', click:function () {

                    } }
                ],
                closable:false,
                timeout:false
            });

        });

        $("#add-tag form").submit(function (e) {
            e.preventDefault();
            var form = $(this);
            var tagNames = $("#tag_names");
            if (tagNames.length > 0) {
                tagNames = tagNames.val();
            } else {
                tagNames = ''
            }
            if (tagNames != '' && $.getCredible.tagCloud.length > 0) {
                var addTag = function () {
                    if ($.getCredible.tagCloud.data('can-vote')) {
                        $.post($.getCredible.tagCloud.data('tag-cloud-path'),
                            form.serialize(), function (data) {
                                tagNamesTextField.tokenInput("clear");
                                $.getCredible.displayNotification('success', 'You have tagged ' + $.getCredible.tagCloud.data('user').full_name + ' with ' + tagNames);
                                $.getCredible.renderTagCloud(data);
                            });
                    } else {
                        $.getCredible.displayNotification('error', 'You cannot vote for yourself')
                    }
                }

                if ($.getCredible.tagCloud.data('logged-in')) {
                    addTag();
                } else {
                    $("#tag_names_after_login").val($("#tag_names").val());
                    $.getCredible.modalApi = $('#login_dialog').modal();
                }
            }
            return false;
        });
    }

    $.getCredible.vote = function (word) {
        var word = $(word);
        var voteToggle;
        if (typeof(this.tagCloudPath) == 'string') {
            if (word.hasClass('vouche') && word.data('tagged')) {
                $.getCredible.displayNotification('error', 'You cannot unvouch the tag you have added');
                return;
            }

            voteToggle = word.hasClass('vouche') ? '/unvote.json' : '/vote.json';
            if (this.tagCloud.data('logged-in') == false) {
                $("#word_id_after_login").val('#' + word.attr('id'));
                $("#tag_names_after_login").val($("#tag_names").val());
                $.getCredible.modalApi = $('#login_dialog').modal();
                return;
            }

            if (this.tagCloud.data('can-vote')) {
                $.post(this.tagCloudPath + '/' + word.data('user-tag-id') + voteToggle, function (data) {
                    if (data.status == 'ok') {
                        var user = $.getCredible.tagCloud.data('user');
                        var voters = $.getCredible.voterImages(data.voters);

                        word.tipsy("hide");
                        word.data('score', data.score);
                        word.data('rank', data.rank);
                        word.data('total', data.total);
                        word.data('voters', voters.join(''));
                        word.data('voters_count', data.voters_count);

                        if (word.hasClass('vouche')) {
                            word.removeClass("vouche").addClass("unvouche");
                            $.getCredible.displayNotification('success', 'You have unvouched for ' + user.full_name + ' on ' + word.text());
                        } else {
                            word.removeClass("unvouche").addClass("vouche");
                            $.getCredible.displayNotification('success', 'You have vouched for ' + user.full_name + ' on ' + word.text());
                        }

                        word.tipsy("show");

                    }
                });
            } else {
                if (!this.tagCloud.data('can-delete')) {
                    $.getCredible.displayNotification('alert', 'You can not vouche for yourself')
                }
            }
        } else {
            $.getCredible.displayNotification('error', 'You are not authorized for this action')
        }
    };

    $.getCredible.voterImages = function (voters) {
        var votersImages = [];
        $.each(voters, function (index, voter) {
            votersImages.push('<img src=' + voter.avatar + ' title=' + voter.name + '/>')
        })

        return votersImages;
    };

    $.getCredible.createWordList = function (data, distributionOptions) {
        var wordList = [];
        var customClass = "word ";
        customClass += this.tagCloud.data('can-delete') ? 'remove ' : '';
        if (data.length == 0) {
            return wordList;
        }
        $.each(data, function (i, userTag) {
            var voters = $.getCredible.voterImages(userTag.voters);

            wordList.push({
                text:userTag.name,
                customClass:function () {
                    var pom = customClass + '';
                    if ($.getCredible.tagCloud.data('can-vote')) {
                        pom += userTag.voted ? "vouche " : "unvouche ";
                    }
                    return pom;
                },
                weight:parseInt((userTag.score - distributionOptions.min) / distributionOptions.divisor),
                title:userTag.name,
                dataAttributes:{ score:userTag.score, 'user-tag-id':userTag.id,
                    rank:userTag.rank, total:userTag.total, tagged:userTag.tagged,
                    voters:voters.join(''), voters_count:userTag.voters_count},
                handlers:{click:function () {
                    $.getCredible.vote(this);
                }}
            });
        });
        return wordList;
    }

    $.getCredible.distributionOptions = function (data) {
        if (data.length === 0) {
            return {min:1, parts:1, divisor:1};
        }

        var min = data[0].score;
        var max = data[0].score;
        var votes = [];
        var parts;
        $.each(data, function (i, userTag) {
            votes.push(userTag.score)
            if (userTag.score > max) {
                max = userTag.score;
            }
            if (userTag.score < min) {
                min = userTag.score;
            }
        });
        var uniqVotes = votes.unique().length;
        if (uniqVotes < 5) {
            var parts = uniqVotes;
        } else {
            var parts = 5;
        }
        var divisor = (max - min) / parts;

        return {min:min, parts:parts, divisor:divisor};
    };


    $.getCredible.renderTagCloud = function (data, tagCloudCallback) {
        var distributionOptions = $.getCredible.distributionOptions(data);
        var wordList = $.getCredible.createWordList(data, distributionOptions);

        $.getCredible.tagCloudLoader.show('fast');
        $.getCredible.tagCloud.html('');
        $.getCredible.tagCloud.jQCloud(wordList, {
            nofollow:true,
            parts:distributionOptions.parts,
            delayedMode:true,
            callback:function () {
                $.getCredible.tagCloudLoader.hide('fast');
                $("#tag-cloud .word").each(function () {
                    var word = $(this);

                    $(this).tipsy({
                        gravity:'sw',
                        fade:true,
                        html:true,
                        delayOut:0,
                        delayIn:350,
                        title:function () {
                            var rank = word.data('rank') ? '#' + word.data('rank') : 'N/A'
                            return '<div class="tag-wrap">' +
                                '<div class="tag-score">' +
                                '<p>score</p>' +
                                '<p class="tag-big">' + word.data('score') + '</p>' +
                                '<p class="tag-place">' + rank + ' out of ' + word.data('total') + '</p>' +
                                '</div>' +
                                '<div class="tag-votes">' +
                                '<p>' + word.data('voters_count') + ' people vouched for you' + '</p>' +
                                '<p>' + word.data('voters') + '</p>' +
                                '</div>' +
                                '</div>';
                        }
                    }).append('<span class="icon"></span>');
                });
                // vote callback after login via modal window
                if (typeof(tagCloudCallback) === 'function') {
                    tagCloudCallback();
                }
            }});
    }

    $.getCredible.updateTagCloud = function (tagCloudCallback) {
        if (this.tagCloud.length > 0) {
            this.tagCloudPath = this.tagCloud.data('tag-cloud-path');
            $.getJSON(this.tagCloud.data('tag-cloud-path'), function (data) {
                $.getCredible.renderTagCloud(data, tagCloudCallback);
            });
        }
    }

    $.getCredible.ajaxPagination = function () {
        var pagination = $('#main .pagination');
        if (pagination.length > 0) {
            pagination.find('a').addClass('js-remote');
        }
    }

    $.getCredible.showFlashMessages = function () {
        var flashMessage = $("#flash-message");
        if (flashMessage.length > 0) {
            var messageType = flashMessage.data('type');
            if (messageType == 'error') {
                $.getCredible.displayNotification('error', flashMessage.text());
            }
            if (messageType == 'alert') {
                $.getCredible.displayNotification('alert', flashMessage.text());
            }
            // if (messageType == 'notice') {
            //     $.getCredible.displayNotification('success', flashMessage.text());
            // }
        }
    }

    $.getCredible.addTagOrVoteAfterLogin = function () {
        if ($("#tag_names_after_login").val() != '') {
            $("#tag_names").val($("#tag_names_after_login").val());
            $("#tag_names_after_login").val('');
            $("#add-tag form").submit();
        }
        if ($('#word_id_after_login').val() != '') {
            $.getCredible.vote($('#word_id_after_login').val());
            $('#word_id_after_login').val('');
        }
    }

    $('#login_dialog #user_sign_in .btn').click(function (e) {
        e.preventDefault();
        var form = $(this).parents('form');

        var params = form.serialize() + '&user_id=' + $.getCredible.tagCloud.data('user-slug');
        $.post("/users/sign_in.json", params, function (data) {
            if (data.success) {
                $('#global-header').replaceWith(data.header);
                $('#tags').replaceWith(data.tag_cloud);
                $.getCredible.init();
                $.getCredible.updateTagCloud(function(){
                    $.getCredible.addTagOrVoteAfterLogin();
                    $.getCredible.modalApi.close();
                });
            } else {
                $.each(data.errors, function (index, text) {
                    $.getCredible.displayNotification('error', text);
                })
            }
        });
    });

    $('#login_dialog #user_sign_up .btn').click(function (e) {
        e.preventDefault();
        var form = $(this).parents('form');

        var params = form.serialize() + '&user_id=' + $.getCredible.tagCloud.data('user-slug');
        $.post("/users.json", params, function (data) {
            if (data.success) {
                $('#global-header').replaceWith(data.header);
                $('#tags').replaceWith(data.tag_cloud);
                $.getCredible.init();
                $.getCredible.updateTagCloud(function(){
                    $.getCredible.addTagOrVoteAfterLogin();
                    $.getCredible.modalApi.close();
                });
            } else {
                $.each(data.errors, function (index, text) {
                    $.getCredible.displayNotification('error', text);
                })
            }
        });
    });

    $('#page').delegate('.js-remote', 'click', function (event) {
        $.ajax({
            url:$(this).attr('href'),
            success:function (data) {
                $('#main').html(data);
                $.getCredible.ajaxPagination();
                $.getCredible.showFlashMessages();
            },
            error:function () {
                $.getCredible.displayNotification('error', 'Something Went Wrong');
            }
        });
        event.preventDefault();
        return false;
    });
    $.getCredible.showFlashMessages();
    $.getCredible.ajaxPagination();
    $.getCredible.init();
    $.getCredible.updateTagCloud();
    $('#slider').rhinoslider({
        autoPlay:true,
        showTime:5000
    });
})
