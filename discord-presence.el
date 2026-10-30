;;; discord-presence.el --- Discord Rich Presence for Emacs -*- lexical-binding: t; -*-

;; A small Discord IPC client intended for a personal Doom Emacs config.

(require 'json)
(require 'project)
(require 'seq)
(require 'subr-x)

(defgroup discord-presence nil
  "Discord Rich Presence for Emacs."
  :group 'applications)

(defcustom discord-presence-client-id ""
  "Discord application ID used for Rich Presence."
  :type 'string)

(defcustom discord-presence-update-delay 2
  "Seconds to wait after buffer changes before updating presence."
  :type 'number)

(defcustom discord-presence-large-image "emacs_logo"
  "Discord application asset key used as the activity's large image."
  :type 'string)

(defvar discord-presence--process nil)
(defvar discord-presence--timer nil)
(defvar discord-presence--buffer "")
(defvar discord-presence--project "")
(defvar discord-presence--ready nil)
(defvar discord-presence--receive-buffer "")
(defvar discord-presence--activity nil)

(defun discord-presence--frame (opcode payload)
  "Encode OPCODE and PAYLOAD as a Discord IPC frame."
  (let* ((bytes (encode-coding-string payload 'utf-8 t))
         (length (string-bytes bytes)))
    (concat (unibyte-string (logand opcode 255) (logand (lsh opcode -8) 255)
                            (logand (lsh opcode -16) 255) (logand (lsh opcode -24) 255)
                            (logand length 255) (logand (lsh length -8) 255)
                            (logand (lsh length -16) 255) (logand (lsh length -24) 255))
            bytes)))

(defun discord-presence--send (opcode object)
  "Send OBJECT using OPCODE to the Discord process."
  (when (process-live-p discord-presence--process)
    (process-send-string
     discord-presence--process
     (discord-presence--frame opcode (json-serialize object)))))

(defun discord-presence--filter (_process data)
  "Process Discord IPC responses and wait for READY before updating."
  (setq discord-presence--receive-buffer
        (concat discord-presence--receive-buffer data))
  (while (>= (length discord-presence--receive-buffer) 8)
    (let* ((bytes (string-to-list (substring discord-presence--receive-buffer 0 8)))
           (opcode (+ (nth 0 bytes) (lsh (nth 1 bytes) 8)
                      (lsh (nth 2 bytes) 16) (lsh (nth 3 bytes) 24)))
           (length (+ (nth 4 bytes) (lsh (nth 5 bytes) 8)
                      (lsh (nth 6 bytes) 16) (lsh (nth 7 bytes) 24))))
      (if (< (length discord-presence--receive-buffer) (+ 8 length))
          (setq bytes nil)
        (let ((payload (decode-coding-string
                        (substring discord-presence--receive-buffer 8 (+ 8 length))
                        'utf-8 t)))
          (setq discord-presence--receive-buffer
                (substring discord-presence--receive-buffer (+ 8 length)))
          (when (and (= opcode 1) (string-match-p "\\\"READY\\\"" payload))
            (setq discord-presence--ready t)
            (discord-presence--send-activity)))))))

(defun discord-presence--send-activity ()
  "Send the most recently prepared activity when Discord is ready."
  (when (and discord-presence--ready discord-presence--activity)
    (discord-presence--send
     1 `((cmd . "SET_ACTIVITY")
         (args . ((pid . ,(emacs-pid)) (activity . ,discord-presence--activity)))
         (nonce . ,(format "%s" (float-time)))))))

(defun discord-presence--sentinel (process _event)
  "Clear the connection variable when PROCESS exits."
  (when (eq process discord-presence--process)
    (setq discord-presence--process nil
          discord-presence--ready nil
          discord-presence--receive-buffer "")))

(defun discord-presence--connect ()
  "Connect to the first available local Discord IPC socket."
  (unless (process-live-p discord-presence--process)
    (let* ((paths
            (append
             (mapcar (lambda (n)
                       (format "%sdiscord-ipc-%d"
                               (file-name-as-directory temporary-file-directory) n))
                     (number-sequence 0 9))
             (mapcar (lambda (n) (format "/tmp/discord-ipc-%d" n))
                     (number-sequence 0 9))))
           (socket (seq-some (lambda (path) (and (file-exists-p path) path)) paths)))
      (when socket
        (condition-case err
            (setq discord-presence--process
                  (make-network-process :name "discord-presence"
                                        :family 'local :service socket
                                        :coding 'binary :noquery t
                                        :filter #'discord-presence--filter
                                        :sentinel #'discord-presence--sentinel))
          (error (setq discord-presence--process nil)
                 (message "Discord Presence: connection failed: %s"
                          (error-message-string err))))
        (when (process-live-p discord-presence--process)
          (discord-presence--send
           0 `((v . 1) (client_id . ,discord-presence-client-id)))))
      (unless socket
        (message "Discord Presence: no Discord IPC socket found; is the desktop app running?")))))

(defun discord-presence--current-project ()
  "Return the current project name, or an empty string."
  (when-let ((project (project-current nil)))
    (file-name-nondirectory
     (directory-file-name (project-root project)))))

(defun discord-presence--update ()
  "Update Discord with the selected buffer and its project."
  (setq discord-presence--timer nil)
  (when (and discord-presence-mode
             (not (string-empty-p discord-presence-client-id))
             (not (minibufferp)))
    (let ((buffer (buffer-name))
          (project (or (discord-presence--current-project) "")))
      (unless (and (equal buffer discord-presence--buffer)
                   (equal project discord-presence--project))
        (setq discord-presence--buffer buffer
              discord-presence--project project))
      (setq discord-presence--activity
            `((type . 0)
              (name . "Emacs")
              (details . ,buffer)
              (state . ,(if (string-empty-p project) "No project" project))
              (assets . ((large_image . ,discord-presence-large-image)
                         (large_text . "GNU Emacs")))
              (instance . :false)))
      (discord-presence--connect)
      (discord-presence--send-activity))))

(defun discord-presence--schedule-update (&rest _)
  "Schedule a debounced presence update."
  (when discord-presence-mode
    (when (timerp discord-presence--timer)
      (cancel-timer discord-presence--timer))
    (setq discord-presence--timer
          (run-with-timer discord-presence-update-delay nil
                          #'discord-presence--update))))

;;;###autoload
(define-minor-mode discord-presence-mode
  "Show the current buffer and project in Discord Rich Presence."
  :global t
  (if discord-presence-mode
      (progn
        (add-hook 'buffer-list-update-hook #'discord-presence--schedule-update)
        (add-hook 'kill-emacs-hook #'discord-presence-stop)
        (discord-presence--schedule-update))
    (remove-hook 'buffer-list-update-hook #'discord-presence--schedule-update)
    (remove-hook 'kill-emacs-hook #'discord-presence-stop)
    (discord-presence-stop)))

;;;###autoload
(defun discord-presence-start ()
  "Start Discord Rich Presence."
  (interactive)
  (discord-presence-mode 1))

;;;###autoload
(defun discord-presence-stop ()
  "Clear Discord Rich Presence and disconnect."
  (interactive)
  (when (timerp discord-presence--timer)
    (cancel-timer discord-presence--timer))
  (setq discord-presence--timer nil)
  (when discord-presence--ready
    (discord-presence--send 1 `((cmd . "SET_ACTIVITY")
                                (args . ((pid . ,(emacs-pid)) (activity . :null)))
                                (nonce . ,(format "%s" (float-time))))))
  (when (process-live-p discord-presence--process)
    (delete-process discord-presence--process))
  (setq discord-presence--process nil
        discord-presence--ready nil
        discord-presence--receive-buffer ""
        discord-presence--activity nil
        discord-presence--buffer ""
        discord-presence--project ""))

;;;###autoload
(defun discord-presence-status ()
  "Display Discord Rich Presence connection status."
  (interactive)
  (message "Discord Presence: %s%s"
           (cond ((not discord-presence-mode) "stopped")
                 ((not (process-live-p discord-presence--process)) "not connected")
                 (discord-presence--ready "connected and ready")
                 (t "connected; waiting for Discord handshake"))
           (if (string-empty-p discord-presence-client-id)
               " (client ID is missing)" "")))

(provide 'discord-presence)
;;; discord-presence.el ends here
