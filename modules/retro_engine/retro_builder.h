/**************************************************************************/
/*  retro_builder.h - asynchronous real-toolchain build runner            */
/**************************************************************************/

#ifndef RETRO_BUILDER_H
#define RETRO_BUILDER_H

#include "retro_project.h"

#include "core/os/mutex.h"
#include "core/os/thread.h"
#include "scene/main/node.h"

class RetroBuilder : public Node {
	GDCLASS(RetroBuilder, Node);

	Ref<RetroProject> project;
	Thread thread;
	Mutex mutex;
	String full_log;
	String running_command;
	Dictionary last_result;
	bool building = false;
	bool cancel_requested = false;
	bool clean_first = false;
	bool debug_build = false;
	String requested_target;

	static void _thread_entry(void *p_user);
	void _run_build();
	int _execute(const String &p_command, bool p_allow_failure = false);
	void _append_line(const String &p_line, int p_level);
	void _parse_diagnostics();
	String _build_command(const String &p_target) const;
	String _clean_command() const;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	RetroBuilder();

	Error build(Ref<RetroProject> p_project, const String &p_target = String(), bool p_clean_first = false, bool p_debug = false);
	Error clean(Ref<RetroProject> p_project);
	void cancel();
	bool is_building() const { return building; }
	String get_last_log() const;
	Dictionary get_last_result() const;
};

#endif // RETRO_BUILDER_H
