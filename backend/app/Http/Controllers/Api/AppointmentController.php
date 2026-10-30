<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class AppointmentController extends Controller
{
    /**
     * Display all appointments and their activity logs.
     */
    public function index()
    {
        return response()->json(
            Appointment::with('logs')->orderByDesc('id')->get()
        );
    }

    /**
     * Create an appointment and schedule its reminder.
     */
    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'service' => ['required', 'string', 'max:160'],
            'destination' => ['required', 'string', 'max:255'],
            'appointment_at' => ['required', 'date'],
            'reminder_at' => [
                'required',
                'date',
                'before:appointment_at',
            ],
            'simulation_mode' => [
                'sometimes',
                Rule::in(['success', 'transient', 'permanent']),
            ],
        ]);

        $validated['status'] = 'scheduled';
        $validated['attempts'] = 0;
        $validated['max_attempts'] = 3;
        $validated['simulation_mode'] =
            $validated['simulation_mode'] ?? 'success';
        $validated['next_attempt_at'] = $validated['reminder_at'];

        $appointment = Appointment::create($validated);

        $appointment->logs()->create([
            'event' => 'appointment_created',
            'level' => 'info',
            'message' => 'Appointment created and reminder scheduled.',
            'attempt' => 0,
            'context' => [
                'simulation_mode' => $appointment->simulation_mode,
            ],
        ]);

        return response()->json([
            'message' => 'Appointment created successfully.',
            'data' => $appointment->load('logs'),
        ], 201);
    }

    /**
     * Display one appointment and its logs.
     */
    public function show(Appointment $appointment)
    {
        return response()->json($appointment->load('logs'));
    }

    /**
     * Schedule or reschedule a reminder.
     */
    public function schedule(Appointment $appointment)
    {
        if (in_array($appointment->status, ['cancelled', 'expired'])) {
            return response()->json([
                'message' =>
                    'Cancelled or expired appointments cannot be scheduled.',
            ], 422);
        }

        if ($appointment->appointment_at->isPast()) {
            return response()->json([
                'message' => 'The appointment date has already passed.',
            ], 422);
        }

        $appointment->update([
            'status' => 'scheduled',
            'attempts' => 0,
            'last_error' => null,
            'delivered_at' => null,
            'next_attempt_at' => $appointment->reminder_at->isPast()
                ? now()
                : $appointment->reminder_at,
        ]);

        $appointment->logs()->create([
            'event' => 'reminder_scheduled',
            'level' => 'info',
            'message' => 'Reminder scheduled for processing.',
            'attempt' => 0,
        ]);

        return response()->json([
            'message' => 'Reminder scheduled.',
            'data' => $appointment->load('logs'),
        ]);
    }

    /**
     * Cancel an appointment and disable its pending reminder.
     */
    public function cancel(Appointment $appointment)
    {
        if (in_array($appointment->status, ['delivered', 'expired'])) {
            return response()->json([
                'message' =>
                    'Delivered or expired appointments cannot be cancelled.',
            ], 422);
        }

        $appointment->update([
            'status' => 'cancelled',
            'next_attempt_at' => null,
        ]);

        $appointment->logs()->create([
            'event' => 'appointment_cancelled',
            'level' => 'info',
            'message' =>
                'Appointment cancelled; pending reminders disabled.',
            'attempt' => $appointment->attempts,
        ]);

        return response()->json([
            'message' => 'Appointment cancelled.',
            'data' => $appointment->load('logs'),
        ]);
    }

    /**
     * Record a human review decision.
     *
     * A reviewer can correct the simulation mode before rescheduling.
     */
    public function resolveReview(
        Request $request,
        Appointment $appointment
    ) {
        $validated = $request->validate([
            'resolution' => [
                'required',
                'string',
                'min:5',
                'max:1000',
            ],
            'simulation_mode' => [
                'sometimes',
                Rule::in(['success', 'transient', 'permanent']),
            ],
        ]);

        if ($appointment->status !== 'manual_review') {
            return response()->json([
                'message' =>
                    'This appointment is not awaiting manual review.',
            ], 422);
        }

        /*
         * Do not reschedule an appointment that has already expired.
         */
        if ($appointment->appointment_at->isPast()) {
            $appointment->update([
                'status' => 'expired',
                'next_attempt_at' => null,
            ]);

            $appointment->logs()->create([
                'event' => 'review_closed_expired',
                'level' => 'warning',
                'message' =>
                    'Review completed, but the appointment has expired.',
                'attempt' => $appointment->attempts,
                'context' => [
                    'resolution' => $validated['resolution'],
                ],
            ]);

            return response()->json([
                'message' =>
                    'Review recorded. Appointment expired and was not rescheduled.',
                'data' => $appointment->load('logs'),
            ]);
        }

        /*
         * Apply the reviewed delivery mode.
         * Defaults to success only when the caller omits this field.
         */
        $newSimulationMode = $validated['simulation_mode']
            ?? $appointment->simulation_mode;

        $appointment->update([
            'status' => 'scheduled',
            'attempts' => 0,
            'last_error' => null,
            'delivered_at' => null,
            'simulation_mode' => $newSimulationMode,
            'next_attempt_at' => $appointment->reminder_at->isPast()
                ? now()
                : $appointment->reminder_at,
        ]);

        $appointment->logs()->create([
            'event' => 'manual_review_resolved',
            'level' => 'info',
            'message' =>
                'Manual review resolved and reminder rescheduled.',
            'attempt' => 0,
            'context' => [
                'resolution' => $validated['resolution'],
                'simulation_mode' => $newSimulationMode,
            ],
        ]);

        return response()->json([
            'message' => 'Review resolved and reminder rescheduled.',
            'data' => $appointment->load('logs'),
        ]);
    }
}